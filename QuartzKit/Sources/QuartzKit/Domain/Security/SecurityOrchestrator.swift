import SwiftUI
import os

/// Centralized app lock orchestrator.
///
/// Manages lock state, inactivity timeout, and biometric authentication.
/// Observed by the app shell to show/hide the lock overlay.
///
/// **Privacy guarantee**: When locked, the UI overlay uses `.regularMaterial`
/// to redact all note content — including in the macOS App Switcher.
@Observable
@MainActor
public final class SecurityOrchestrator {

    // MARK: - Persisted Settings

    /// Whether the user has enabled app lock.
    public var isAppLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.appLockEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.appLockEnabledKey) }
    }

    /// Minutes of inactivity before the app locks. 0 = lock immediately on background.
    public var lockTimeoutMinutes: Int {
        get { UserDefaults.standard.object(forKey: Self.lockTimeoutKey) != nil
            ? UserDefaults.standard.integer(forKey: Self.lockTimeoutKey)
            : 5
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.lockTimeoutKey) }
    }

    // MARK: - Runtime State

    /// True when the app is locked and the content overlay should be shown.
    public private(set) var isLocked: Bool = false

    /// True while a biometric authentication prompt is in progress.
    public private(set) var isAuthenticating: Bool = false

    /// Error message from the last failed authentication attempt.
    public var authError: String?

    // MARK: - Private

    private let authService = BiometricAuthService()
    private let logger = Logger(subsystem: "com.quartz", category: "Security")

    /// Timestamp when the app last entered the background.
    private var backgroundTimestamp: Date?

    private static let appLockEnabledKey = "quartz.appLockEnabled"
    private static let lockTimeoutKey = "quartz.lockTimeoutMinutes"

    // MARK: - Init

    /// Shared instance for use across Settings and the app shell.
    /// Both read/write the same UserDefaults keys, so state is consistent.
    public static let shared = SecurityOrchestrator()

    public init() {
        // If app lock is enabled, start locked on launch
        if UserDefaults.standard.bool(forKey: Self.appLockEnabledKey) {
            isLocked = true
            logger.info("App lock enabled — starting locked")
        }
    }

    // MARK: - Scene Phase Handling

    /// Called when the app's scene phase changes.
    /// Records background timestamp and checks timeout on foreground return.
    public func scenePhaseDidChange(to phase: ScenePhase) {
        guard isAppLockEnabled else { return }

        switch phase {
        case .background:
            backgroundTimestamp = Date()
            logger.debug("App entered background — timestamp recorded")

        case .active:
            // Don't re-lock while authentication is in progress
            guard !isAuthenticating else { return }
            guard let bgTime = backgroundTimestamp else { return }
            let elapsed = Date().timeIntervalSince(bgTime)
            let timeoutSeconds = TimeInterval(lockTimeoutMinutes * 60)
            backgroundTimestamp = nil

            if elapsed >= timeoutSeconds {
                logger.info("Inactivity timeout exceeded (\(Int(elapsed))s > \(self.lockTimeoutMinutes * 60)s) — locking")
                lock()
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Lock / Unlock

    /// Locks the app immediately.
    public func lock() {
        guard isAppLockEnabled else { return }
        isLocked = true
        authError = nil
    }

    /// Attempts biometric authentication to unlock the app.
    /// Guarded against re-entry — concurrent calls are ignored.
    public func authenticate() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        authError = nil

        let result = await authService.authenticate(
            reason: String(localized: "Unlock Quartz to access your notes", bundle: .module)
        )

        switch result {
        case .success:
            logger.info("Authentication successful — unlocking")
            isLocked = false
            authError = nil
            QuartzFeedback.success()

        case .cancelled:
            logger.debug("Authentication cancelled by user")
            // Don't show error for user-initiated cancel

        case .failed(let message):
            logger.warning("Authentication failed: \(message)")
            QuartzDiagnostics.warning(
                category: "Security",
                "Authentication failed: \(message)"
            )
            authError = message
            QuartzFeedback.warning()
        }
    }

    // MARK: - Biometry Info

    /// Returns the SF Symbol name for the current biometry type.
    public var biometryIconName: String {
        let type = biometryType
        switch type {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .passcodeOnly, .none: return "lock.fill"
        }
    }

    /// Returns a human-readable label for the biometry type.
    public var biometryLabel: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcodeOnly: return String(localized: "Passcode", bundle: .module)
        case .none: return String(localized: "Not Available", bundle: .module)
        }
    }

    /// Whether any form of device authentication is available.
    public var isAuthenticationAvailable: Bool {
        biometryType != .none
    }

    private var biometryType: BiometricAuthService.BiometryType {
        // BiometricAuthService is an actor — but availableBiometry() is synchronous
        // and safe to call from any context since LAContext is thread-safe for queries.
        let service = BiometricAuthService()
        // Use a nonisolated wrapper to avoid actor hop for this sync check
        return _syncBiometryCheck()
    }

    private nonisolated func _syncBiometryCheck() -> BiometricAuthService.BiometryType {
        let context = __LocalAuthContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return .passcodeOnly
            }
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        @unknown default: return .passcodeOnly
        }
    }
}

// Thin wrapper to avoid importing LocalAuthentication in the header
import LocalAuthentication
private typealias __LocalAuthContext = LAContext
