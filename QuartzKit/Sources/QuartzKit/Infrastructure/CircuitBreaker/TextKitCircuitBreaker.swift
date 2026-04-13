import Foundation
import os

// MARK: - TextKit Circuit Breaker

/// Circuit breaker for TextKit operations protecting against malicious inputs.
///
/// **Hostile OS Threats:**
/// - **Regex catastrophic backtracking**: Malicious patterns like `(a+)+$` freeze parser
/// - **50MB base64 paste**: Clipboard injection causing OOM
/// - **10,000 zero-width joiners**: Unicode exploits crashing NSAttributedString
/// - **Deeply nested markdown**: Stack overflow in recursive AST traversal
///
/// **Telemetry Signature:**
/// - `os_signpost` interval: "TextKit.parse" with duration
/// - `Logger.fault()` on circuit trip with input characteristics
/// - `NotificationCenter`: `.quartzTextKitCircuitTripped`
///
/// **Degradation Strategy:**
/// 1. **Normal**: Full AST parsing + syntax highlighting
/// 2. **Degraded**: Simplified regex-only highlighting (no AST)
/// 3. **PlainText**: No highlighting, raw monospace text
/// 4. **Rejected**: Input too dangerous, show error state
@MainActor
public final class TextKitCircuitBreaker: @unchecked Sendable {
    private struct ScanResult {
        let poisonPill: PoisonPillType?
        let longLineLength: Int?
    }

    // MARK: - Singleton

    public static let shared = TextKitCircuitBreaker()

    // MARK: - State

    /// Current circuit state.
    public private(set) var state: CircuitState = .normal

    /// Number of consecutive failures before tripping.
    private let failureThreshold: Int = 2

    /// Current failure count.
    private var failureCount: Int = 0

    /// Cooldown before attempting recovery.
    private var cooldownDuration: TimeInterval = 10.0

    /// Last trip time.
    private var lastTripTime: Date?

    /// Recovery task.
    private var recoveryTask: Task<Void, Never>?

    // MARK: - Thresholds (Poison Pill Detection)

    /// Maximum document size (characters) before rejection.
    public static let maxDocumentSize = 500_000  // 500KB

    /// Maximum line length before degrading.
    public static let maxLineLength = 10_000

    /// Maximum consecutive zero-width characters before rejection.
    public static let maxZeroWidthRun = 100

    /// Maximum nesting depth for AST traversal.
    public static let maxNestingDepth = 50

    /// Parsing timeout in milliseconds.
    public static let parseTimeoutMs: UInt64 = 500

    // MARK: - Private

    private let logger = Logger(subsystem: "com.quartz", category: "TextKitCircuitBreaker")
    private let signpostLog = OSLog(subsystem: "com.quartz", category: .pointsOfInterest)
    private static let regexBombPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\([\w\+\*]+\)\+"#),
        try! NSRegularExpression(pattern: #"(\|.+){10,}"#)
    ]

    // MARK: - Init

    private init() {}

    // MARK: - Circuit State

    public enum CircuitState: String, Sendable {
        /// Full AST parsing + syntax highlighting.
        case normal = "normal"

        /// Simplified highlighting (no AST, basic regex).
        case degraded = "degraded"

        /// No highlighting, plain text only.
        case plainText = "plainText"

        /// Input rejected as malicious.
        case rejected = "rejected"

        /// Display name for UI.
        public var displayName: String {
            switch self {
            case .normal: return "Full Highlighting"
            case .degraded: return "Basic Highlighting"
            case .plainText: return "Plain Text Mode"
            case .rejected: return "Content Blocked"
            }
        }
    }

    // MARK: - Input Validation

    /// Validates input and returns the appropriate processing mode.
    /// Call before ANY text processing operation.
    public func validateInput(_ text: String) -> InputValidation {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "TextKit.validate", signpostID: signpostID)
        defer { os_signpost(.end, log: signpostLog, name: "TextKit.validate", signpostID: signpostID) }
        let utf8Count = text.utf8.count

        // Check document size
        if utf8Count > Self.maxDocumentSize {
            logger.warning("Document exceeds max size: \(utf8Count) > \(Self.maxDocumentSize)")
            return .degraded(reason: .documentTooLarge(size: utf8Count))
        }

        let scanResult = scanText(text, utf8Count: utf8Count)

        // Check for poison pill patterns
        if let poisonPill = scanResult.poisonPill {
            recordFailure(reason: "Poison pill detected: \(poisonPill)")
            return .rejected(reason: poisonPill)
        }

        if let longLineLength = scanResult.longLineLength {
            logger.warning("Line too long: \(longLineLength) characters")
            return .degraded(reason: .lineTooLong(length: longLineLength))
        }

        // If circuit is tripped, enforce degraded mode
        switch state {
        case .normal:
            return .allowed
        case .degraded:
            return .degraded(reason: .circuitTripped)
        case .plainText:
            return .plainTextOnly(reason: .circuitTripped)
        case .rejected:
            return .rejected(reason: .circuitRejected)
        }
    }

    /// Scans the text once for poison pills and pathological line lengths.
    private func scanText(_ text: String, utf8Count: Int) -> ScanResult {
        if let asciiResult = scanASCIIText(text, utf8Count: utf8Count) {
            return asciiResult
        }

        return scanUnicodeText(text, utf8Count: utf8Count)
    }

    /// Fast path for typical editor content, which is overwhelmingly ASCII.
    private func scanASCIIText(_ text: String, utf8Count: Int) -> ScanResult? {
        var currentLineLength = 0
        var longestLineLength: Int?
        let shouldEvaluateBase64 = utf8Count > 100_000
        var base64LikeByteCount = 0

        for byte in text.utf8 {
            guard byte < 0x80 else {
                return nil
            }

            switch byte {
            case 0x0A, 0x0D:
                if currentLineLength > Self.maxLineLength {
                    longestLineLength = max(longestLineLength ?? 0, currentLineLength)
                }
                currentLineLength = 0
            default:
                currentLineLength += 1
            }

            if shouldEvaluateBase64, isASCIIBase64Byte(byte) {
                base64LikeByteCount += 1
            }
        }

        if currentLineLength > Self.maxLineLength {
            longestLineLength = max(longestLineLength ?? 0, currentLineLength)
        }

        if shouldEvaluateBase64, utf8Count > 0 {
            let base64Ratio = Double(base64LikeByteCount) / Double(utf8Count)
            if base64Ratio > 0.95 {
                return ScanResult(
                    poisonPill: .base64Blob(size: utf8Count),
                    longLineLength: longestLineLength
                )
            }
        }

        if utf8Count < 500 && text.contains("(") && text.contains("+") {
            for regex in Self.regexBombPatterns {
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    return ScanResult(
                        poisonPill: .suspiciousPattern,
                        longLineLength: longestLineLength
                    )
                }
            }
        }

        return ScanResult(poisonPill: nil, longLineLength: longestLineLength)
    }

    private func scanUnicodeText(_ text: String, utf8Count: Int) -> ScanResult {
        var zeroWidthRun = 0
        var controlChars = 0
        var currentLineLength = 0
        var longestLineLength: Int?
        let shouldEvaluateBase64 = utf8Count > 100_000
        var totalScalarCount = 0
        var base64LikeScalarCount = 0

        for scalar in text.unicodeScalars {
            totalScalarCount += 1

            if scalar == "\n" || scalar == "\r" {
                if currentLineLength > Self.maxLineLength {
                    longestLineLength = max(longestLineLength ?? 0, currentLineLength)
                }
                currentLineLength = 0
            } else {
                currentLineLength += 1
            }

            if isZeroWidth(scalar) {
                zeroWidthRun += 1
                if zeroWidthRun >= Self.maxZeroWidthRun {
                    return ScanResult(
                        poisonPill: .zeroWidthFlood(count: zeroWidthRun),
                        longLineLength: nil
                    )
                }
            } else {
                zeroWidthRun = 0
            }

            if scalar.properties.isDefaultIgnorableCodePoint {
                controlChars += 1
                if controlChars > 1000 {
                    return ScanResult(
                        poisonPill: .controlCharFlood(count: controlChars),
                        longLineLength: nil
                    )
                }
            }

            if shouldEvaluateBase64, isBase64Scalar(scalar) {
                base64LikeScalarCount += 1
            }
        }

        if currentLineLength > Self.maxLineLength {
            longestLineLength = max(longestLineLength ?? 0, currentLineLength)
        }

        // Check for base64-encoded large blobs (potential image injection).
        if shouldEvaluateBase64, totalScalarCount > 0 {
            let base64Ratio = Double(base64LikeScalarCount) / Double(totalScalarCount)
            if base64Ratio > 0.95 {
                return ScanResult(
                    poisonPill: .base64Blob(size: utf8Count),
                    longLineLength: longestLineLength
                )
            }
        }

        // Check for regex bomb patterns (exponential backtracking).
        if utf8Count < 500 && text.contains("(") && text.contains("+") {
            for regex in Self.regexBombPatterns {
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    return ScanResult(
                        poisonPill: .suspiciousPattern,
                        longLineLength: longestLineLength
                    )
                }
            }
        }

        return ScanResult(poisonPill: nil, longLineLength: longestLineLength)
    }

    private func isASCIIBase64Byte(_ byte: UInt8) -> Bool {
        switch byte {
        case 43, 47, 61, 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private func isBase64Scalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 43, 47, 61, 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    /// Checks if a Unicode scalar is a zero-width character.
    private func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B...0x200D,  // Zero-width space, ZWNJ, ZWJ
             0x2060...0x2064,  // Word joiner, invisible separators
             0xFEFF,           // BOM / ZWNBSP
             0x034F,           // Combining grapheme joiner
             0x061C,           // Arabic letter mark
             0x115F...0x1160,  // Hangul fillers
             0x17B4...0x17B5,  // Khmer vowel inherent
             0x180B...0x180E:  // Mongolian free variation selectors
            return true
        default:
            return false
        }
    }

    // MARK: - Timeout-Protected Parsing

    /// Executes a parsing operation with strict timeout.
    /// If timeout is exceeded, trips circuit and returns nil.
    public func timedParse<T: Sendable>(
        timeout: Duration = .milliseconds(500),
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "TextKit.parse", signpostID: signpostID)

        let startTime = DispatchTime.now()

        do {
            let result = try await withThrowingTaskGroup(of: T?.self) { group in
                // Main parsing task
                group.addTask {
                    await operation()
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }

                // Return first to complete
                if let result = try await group.next() {
                    group.cancelAll()

                    let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

                    os_signpost(.end, log: signpostLog, name: "TextKit.parse", signpostID: signpostID, "duration=%{public}.2fms", durationMs)

                    // Record success
                    if result != nil {
                        recordSuccess()
                    }

                    return result
                }

                os_signpost(.end, log: signpostLog, name: "TextKit.parse", signpostID: signpostID, "timeout")
                return nil
            }

            return result

        } catch {
            os_signpost(.end, log: signpostLog, name: "TextKit.parse", signpostID: signpostID, "error")

            // Timeout occurred — trip circuit
            recordFailure(reason: "Parse timeout exceeded \(timeout.components.seconds * 1000)ms")
            return nil
        }
    }

    // MARK: - Circuit Management

    private func recordFailure(reason: String) {
        failureCount += 1
        logger.warning("TextKit failure #\(self.failureCount): \(reason, privacy: .public)")

        if failureCount >= failureThreshold {
            tripCircuit(reason: reason)
        }
    }

    private func recordSuccess() {
        // If we're in degraded state and things are working, try to recover
        if state == .degraded {
            failureCount = max(0, failureCount - 1)
            if failureCount == 0 {
                attemptRecovery()
            }
        }
    }

    private func tripCircuit(reason: String) {
        let previousState = state

        switch state {
        case .normal:
            state = .degraded
        case .degraded:
            state = .plainText
        case .plainText, .rejected:
            // Already at maximum degradation
            break
        }

        failureCount = 0
        lastTripTime = Date()

        if state != previousState {
            logger.fault("TextKit circuit tripped: \(previousState.rawValue) → \(self.state.rawValue). Reason: \(reason, privacy: .public)")

            // Notify observers
            NotificationCenter.default.post(
                name: .quartzTextKitCircuitTripped,
                object: nil,
                userInfo: [
                    "previousState": previousState.rawValue,
                    "newState": state.rawValue,
                    "reason": reason
                ]
            )

            // Schedule recovery
            scheduleRecovery()
        }
    }

    private func scheduleRecovery() {
        recoveryTask?.cancel()
        recoveryTask = Task {
            try? await Task.sleep(for: .seconds(cooldownDuration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.attemptRecovery()
            }
        }
    }

    private func attemptRecovery() {
        guard state != .normal else { return }

        logger.info("Attempting TextKit circuit recovery from \(self.state.rawValue)")

        switch state {
        case .plainText:
            state = .degraded
        case .degraded:
            state = .normal
        case .normal, .rejected:
            break
        }

        // Increase cooldown for next failure (exponential backoff)
        cooldownDuration = min(cooldownDuration * 1.5, 60.0)

        NotificationCenter.default.post(
            name: .quartzTextKitCircuitRecovered,
            object: nil,
            userInfo: ["state": state.rawValue]
        )
    }

    /// Manually resets the circuit to normal state.
    public func reset() {
        recoveryTask?.cancel()
        failureCount = 0
        cooldownDuration = 10.0
        state = .normal
        logger.info("TextKit circuit manually reset")
    }
}

// MARK: - Supporting Types

public extension TextKitCircuitBreaker {

    /// Result of input validation.
    enum InputValidation: Sendable {
        case allowed
        case degraded(reason: DegradationReason)
        case plainTextOnly(reason: DegradationReason)
        case rejected(reason: PoisonPillType)

        public var canHighlight: Bool {
            switch self {
            case .allowed, .degraded: return true
            case .plainTextOnly, .rejected: return false
            }
        }

        public var useFullAST: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    /// Reasons for degraded highlighting.
    enum DegradationReason: Sendable {
        case documentTooLarge(size: Int)
        case lineTooLong(length: Int)
        case circuitTripped
    }

    /// Types of detected malicious input.
    enum PoisonPillType: Sendable, CustomStringConvertible {
        case zeroWidthFlood(count: Int)
        case base64Blob(size: Int)
        case suspiciousPattern
        case controlCharFlood(count: Int)
        case circuitRejected

        public var description: String {
            switch self {
            case .zeroWidthFlood(let count):
                return "Zero-width character flood (\(count) chars)"
            case .base64Blob(let size):
                return "Suspicious base64 blob (\(size / 1024)KB)"
            case .suspiciousPattern:
                return "Suspicious regex-like pattern"
            case .controlCharFlood(let count):
                return "Control character flood (\(count) chars)"
            case .circuitRejected:
                return "Content rejected by circuit breaker"
            }
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when the TextKit circuit breaker trips.
    static let quartzTextKitCircuitTripped = Notification.Name("quartzTextKitCircuitTripped")

    /// Posted when the TextKit circuit breaker recovers.
    static let quartzTextKitCircuitRecovered = Notification.Name("quartzTextKitCircuitRecovered")
}
