import Foundation

/// Persistent diagnostics store for exportable support logs.
///
/// Quartz still writes to Apple's unified logging system, but this actor keeps a
/// lightweight rolling text log inside the app sandbox so TestFlight builds can
/// export recent warnings, errors, faults, and important readiness telemetry.
public actor QuartzDiagnosticsStore {
    public enum Level: String, Sendable, Codable {
        case info
        case warning
        case error
        case fault
    }

    public static let shared = QuartzDiagnosticsStore()

    private let maximumLogBytes: Int
    private let customLogURL: URL?
    private let formatter: ISO8601DateFormatter
    private var resolvedLogURL: URL?

    internal init(logURL: URL? = nil, maximumLogBytes: Int = 262_144) {
        self.customLogURL = logURL
        self.maximumLogBytes = maximumLogBytes
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func record(level: Level, category: String, message: String) {
        guard let logURL = ensureLogURL() else { return }
        let normalizedMessage = DiagnosticPrivacy.sanitizeFreeformMessage(message)
        let line = "\(formatter.string(from: Date())) [\(level.rawValue.uppercased())] [\(category)] \(normalizedMessage)\n"
        guard let data = line.data(using: .utf8) else { return }

        append(data: data, to: logURL)
        trimIfNeeded(at: logURL)
    }

    public func recentLogText(limitBytes: Int? = nil) -> String {
        guard let logURL = ensureLogURL(),
              let data = try? Data(contentsOf: logURL),
              !data.isEmpty else {
            return "No diagnostics captured yet."
        }

        let selectedData: Data
        if let limitBytes {
            let lowerBound = max(0, data.count - limitBytes)
            let suffix = data[lowerBound...]
            if lowerBound == 0 {
                selectedData = Data(suffix)
            } else if let newlineIndex = suffix.firstIndex(of: 0x0A) {
                selectedData = Data(suffix[suffix.index(after: newlineIndex)...])
            } else {
                selectedData = Data(suffix)
            }
        } else {
            selectedData = data
        }

        return String(decoding: selectedData, as: UTF8.self)
    }

    public func logFileURL() -> URL? {
        ensureLogURL()
    }

    private func ensureLogURL() -> URL? {
        if let resolvedLogURL {
            return resolvedLogURL
        }

        if let customLogURL {
            let directory = customLogURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            resolvedLogURL = customLogURL
            return customLogURL
        }

        guard let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "Quartz"
        let diagnosticsDirectory = baseDirectory
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)

        let logURL = diagnosticsDirectory.appending(path: "diagnostics.log")
        resolvedLogURL = logURL
        return logURL
    }

    private func append(data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? data.write(to: url, options: .atomic)
                return
            }

            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
                try? data.write(to: url, options: .atomic)
            }
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private func trimIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > maximumLogBytes,
              let existingData = try? Data(contentsOf: url),
              !existingData.isEmpty else {
            return
        }

        let lowerBound = max(0, existingData.count - maximumLogBytes)
        let suffix = existingData[lowerBound...]
        let trimmedData: Data
        if lowerBound == 0 {
            trimmedData = Data(suffix)
        } else if let newlineIndex = suffix.firstIndex(of: 0x0A) {
            trimmedData = Data(suffix[suffix.index(after: newlineIndex)...])
        } else {
            trimmedData = Data(suffix)
        }

        try? trimmedData.write(to: url, options: .atomic)
    }
}

public enum QuartzDiagnostics {
    public static func info(category: String, _ message: String) {
        SubsystemDiagnostics.recordLegacy(level: .info, category: category, message: message)
        Task(priority: .utility) {
            await QuartzDiagnosticsStore.shared.record(level: .info, category: category, message: message)
        }
    }

    public static func warning(category: String, _ message: String) {
        SubsystemDiagnostics.recordLegacy(level: .warning, category: category, message: message)
        Task(priority: .utility) {
            await QuartzDiagnosticsStore.shared.record(level: .warning, category: category, message: message)
        }
    }

    public static func error(category: String, _ message: String) {
        SubsystemDiagnostics.recordLegacy(level: .error, category: category, message: message)
        Task(priority: .utility) {
            await QuartzDiagnosticsStore.shared.record(level: .error, category: category, message: message)
        }
    }

    public static func fault(category: String, _ message: String) {
        SubsystemDiagnostics.recordLegacy(level: .error, category: category, message: message)
        Task(priority: .utility) {
            await QuartzDiagnosticsStore.shared.record(level: .fault, category: category, message: message)
        }
    }
}
