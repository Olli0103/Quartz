import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Verwaltet Assets (Bilder, Dateien) innerhalb eines Vaults.
///
/// Bilder werden in einen `assets/` Unterordner kopiert und
/// relative Markdown-Links werden automatisch generiert.
public actor AssetManager {
    private let fileManager = FileManager.default

    /// Name des Asset-Ordners innerhalb des Vaults.
    private let assetFolderName = "assets"

    public init() {}

    /// Importiert eine Bilddatei in den Vault und gibt den relativen Markdown-Link zurück.
    ///
    /// - Parameters:
    ///   - sourceURL: Quell-URL des Bildes
    ///   - vaultRoot: Root-URL des Vaults
    ///   - noteURL: URL der Notiz (für relative Pfadberechnung)
    /// - Returns: Relativer Markdown-Image-Link, z.B. `![image](assets/photo-2026.png)`
    public func importImage(
        from sourceURL: URL,
        vaultRoot: URL,
        noteURL: URL
    ) async throws -> String {
        let assetsFolder = try ensureAssetsFolder(in: vaultRoot)
        let destinationURL = uniqueDestination(
            for: sourceURL.lastPathComponent,
            in: assetsFolder
        )

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )

        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }

    #if canImport(UIKit)
    /// Importiert ein UIImage (z.B. aus Paste/Drag) in den Vault.
    public func importImage(
        _ image: UIImage,
        named name: String? = nil,
        vaultRoot: URL,
        noteURL: URL
    ) async throws -> String {
        let assetsFolder = try ensureAssetsFolder(in: vaultRoot)
        let fileName = name ?? "image-\(Self.timestamp()).png"
        let destinationURL = uniqueDestination(for: fileName, in: assetsFolder)

        guard let data = image.pngData() else {
            throw AssetError.conversionFailed
        }
        try data.write(to: destinationURL, options: .atomic)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )
        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }
    #endif

    #if canImport(AppKit)
    /// Importiert ein NSImage (z.B. aus Paste/Drag) in den Vault.
    public func importImage(
        _ image: NSImage,
        named name: String? = nil,
        vaultRoot: URL,
        noteURL: URL
    ) async throws -> String {
        let assetsFolder = try ensureAssetsFolder(in: vaultRoot)
        let fileName = name ?? "image-\(Self.timestamp()).png"
        let destinationURL = uniqueDestination(for: fileName, in: assetsFolder)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw AssetError.conversionFailed
        }
        try pngData.write(to: destinationURL, options: .atomic)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )
        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }
    #endif

    /// Löscht ein Asset und entfernt den zugehörigen Link aus dem Markdown.
    public func deleteAsset(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    /// Gibt alle Assets im Vault zurück.
    public func listAssets(in vaultRoot: URL) throws -> [URL] {
        let assetsFolder = vaultRoot.appending(path: assetFolderName)
        guard fileManager.fileExists(atPath: assetsFolder.path(percentEncoded: false)) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: assetsFolder,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    // MARK: - Private

    private func ensureAssetsFolder(in vaultRoot: URL) throws -> URL {
        let assetsFolder = vaultRoot.appending(path: assetFolderName)
        if !fileManager.fileExists(atPath: assetsFolder.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        }
        return assetsFolder
    }

    private func uniqueDestination(for fileName: String, in folder: URL) -> URL {
        var url = folder.appending(path: fileName)
        var counter = 1

        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        while fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            let newName = "\(name)-\(counter).\(ext)"
            url = folder.appending(path: newName)
            counter += 1
        }
        return url
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let basePath = base.path(percentEncoded: false)
        let targetPath = target.path(percentEncoded: false)

        // Einfacher Fall: Target ist unter Base
        if targetPath.hasPrefix(basePath) {
            return String(targetPath.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        // Fallback: Nur Dateiname
        return "\(assetFolderName)/\(target.lastPathComponent)"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Errors

public enum AssetError: LocalizedError, Sendable {
    case conversionFailed
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .conversionFailed:
            "Failed to convert image data"
        case .fileNotFound(let url):
            "Asset not found: \(url.lastPathComponent)"
        }
    }
}
