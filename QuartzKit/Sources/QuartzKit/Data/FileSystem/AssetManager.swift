import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Manages assets (images, files) within a vault.
///
/// Images are copied into an `assets/` subfolder and
/// relative Markdown links are generated automatically.
public actor AssetManager {
    private let fileManager = FileManager.default
    private let writer = CoordinatedFileWriter.shared

    /// Name of the asset folder within the vault.
    private let assetFolderName = "assets"

    public init() {}

    /// Imports an image file into the vault and returns the relative Markdown link.
    ///
    /// - Parameters:
    ///   - sourceURL: Source URL of the image
    ///   - vaultRoot: Root URL of the vault
    ///   - noteURL: URL of the note (for relative path calculation)
    /// - Returns: Relative Markdown image link, e.g. `![image](assets/photo-2026.png)`
    public func importImage(
        from sourceURL: URL,
        vaultRoot: URL,
        noteURL: URL
    ) async throws -> String {
        // Prevent symlink-based path traversal
        let resourceValues = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw AssetError.symlinkNotAllowed
        }

        let assetsFolder = try ensureAssetsFolder(in: vaultRoot)
        let destinationURL = uniqueDestination(
            for: sourceURL.lastPathComponent,
            in: assetsFolder
        )

        try writer.copyItem(from: sourceURL, to: destinationURL)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )

        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }

    #if canImport(UIKit)
    /// Imports a UIImage (e.g. from paste/drag) into the vault.
    public func importImage(
        _ image: sending UIImage,
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
        try writer.write(data, to: destinationURL)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )
        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }
    #endif

    #if canImport(AppKit)
    /// Imports an NSImage (e.g. from paste/drag) into the vault.
    public func importImage(
        _ image: sending NSImage,
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
        try writer.write(pngData, to: destinationURL)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )
        let altText = destinationURL.deletingPathExtension().lastPathComponent
        return "![\(altText)](\(relativePath))"
    }
    #endif

    // MARK: - Generic Asset Import (Drag-and-Drop)

    /// Supported media types for drag-and-drop import.
    public static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "tif", "bmp", "heic", "heif"
    ]

    public static let supportedDocumentExtensions: Set<String> = [
        "pdf"
    ]

    public static var supportedExtensions: Set<String> {
        supportedImageExtensions.union(supportedDocumentExtensions)
    }

    /// Checks whether a file URL has a supported media extension.
    public static func isSupportedAsset(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Imports any supported asset file into the vault and returns the Markdown link string.
    ///
    /// - Images produce `![altText](assets/file.png)`
    /// - PDFs produce `[fileName](assets/file.pdf)`
    ///
    /// - Parameters:
    ///   - sourceURL: Source URL of the file on disk
    ///   - vaultRoot: Root URL of the vault
    ///   - noteURL: URL of the current note (for relative path calculation)
    /// - Returns: Markdown link string to insert into the editor
    public func importAsset(
        from sourceURL: URL,
        vaultRoot: URL,
        noteURL: URL
    ) async throws -> String {
        // Prevent symlink-based path traversal
        let resourceValues = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw AssetError.symlinkNotAllowed
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw AssetError.unsupportedFileType(sourceURL.pathExtension)
        }

        let assetsFolder = try ensureAssetsFolder(in: vaultRoot)
        let destinationURL = uniqueDestination(
            for: sourceURL.lastPathComponent,
            in: assetsFolder
        )

        try writer.copyItem(from: sourceURL, to: destinationURL)

        let relativePath = self.relativePath(
            from: noteURL.deletingLastPathComponent(),
            to: destinationURL
        )

        let altText = destinationURL.deletingPathExtension().lastPathComponent

        if Self.supportedImageExtensions.contains(ext) {
            return "![\(altText)](\(relativePath))"
        } else {
            // Non-image assets (PDFs) use regular link syntax
            return "[\(altText)](\(relativePath))"
        }
    }

    /// Deletes an asset and removes the associated link from the Markdown.
    public func deleteAsset(at url: URL) throws {
        try writer.removeItem(at: url)
    }

    /// Returns all assets in the vault.
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
            try writer.createDirectory(at: assetsFolder)
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
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents

        var commonLength = 0
        for i in 0..<min(baseComponents.count, targetComponents.count) {
            if baseComponents[i] == targetComponents[i] {
                commonLength = i + 1
            } else {
                break
            }
        }

        let upCount = baseComponents.count - commonLength
        let ups = Array(repeating: "..", count: upCount)
        let remaining = targetComponents.count > commonLength
            ? Array(targetComponents[commonLength...])
            : []

        let parts = ups + remaining
        guard !parts.isEmpty else { return target.lastPathComponent }
        return parts.joined(separator: "/")
    }

    /// Thread-safe timestamp generator. Creates a new formatter per call to avoid
    /// data races (DateFormatter is not thread-safe).
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Errors

public enum AssetError: LocalizedError, Sendable {
    case conversionFailed
    case fileNotFound(URL)
    case symlinkNotAllowed
    case unsupportedFileType(String)

    public var errorDescription: String? {
        switch self {
        case .conversionFailed:
            String(localized: "Failed to convert image data", bundle: .module)
        case .fileNotFound(let url):
            String(localized: "Asset not found: \(url.lastPathComponent)", bundle: .module)
        case .symlinkNotAllowed:
            String(localized: "Symbolic links are not supported for asset import", bundle: .module)
        case .unsupportedFileType(let ext):
            String(localized: "Unsupported file type: \(ext)", bundle: .module)
        }
    }
}
