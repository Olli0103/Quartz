#if canImport(PencilKit)
import Foundation
import PencilKit
import os
#if canImport(AppKit)
import AppKit
#endif

/// Service for saving and loading PencilKit drawings.
///
/// Drawings are stored as `.drawing` files in the `assets/` folder
/// next to the associated note. In Markdown they are embedded
/// as `![[drawing-id.drawing]]`.
public actor DrawingStorageService {
    private let fileManager = FileManager.default
    private let writer = CoordinatedFileWriter.shared
    private let logger = Logger(subsystem: "com.quartz", category: "DrawingStorage")

    public init() {}

    /// Saves a drawing as a `.drawing` file.
    ///
    /// - Parameters:
    ///   - drawing: The PencilKit drawing
    ///   - drawingID: Unique ID of the drawing
    ///   - noteURL: URL of the associated note
    /// - Returns: Relative path to the drawing file (for Markdown embed)
    public func save(
        drawing: PKDrawing,
        drawingID: String,
        noteURL: URL
    ) throws -> String {
        let assetsFolder = assetsURL(for: noteURL)
        try writer.createDirectory(at: assetsFolder)

        let fileName = "\(drawingID).drawing"
        let fileURL = assetsFolder.appending(path: fileName)

        let data = drawing.dataRepresentation()
        try writer.write(data, to: fileURL)

        // Save thumbnail as PNG
        let thumbnailURL = assetsFolder.appending(path: "\(drawingID).png")
        try saveThumbnail(drawing: drawing, to: thumbnailURL)

        return "assets/\(fileName)"
    }

    /// Loads a drawing from a `.drawing` file.
    public func load(drawingID: String, noteURL: URL) throws -> PKDrawing {
        let assetsFolder = assetsURL(for: noteURL)
        let fileURL = assetsFolder.appending(path: "\(drawingID).drawing")

        let data = try writer.read(from: fileURL)
        return try PKDrawing(data: data)
    }

    /// Deletes a drawing and its thumbnail.
    public func delete(drawingID: String, noteURL: URL) throws {
        let assetsFolder = assetsURL(for: noteURL)

        let drawingURL = assetsFolder.appending(path: "\(drawingID).drawing")
        let thumbnailURL = assetsFolder.appending(path: "\(drawingID).png")

        try writer.removeItem(at: drawingURL)
        // Thumbnail deletion is best-effort since the drawing file is primary
        do {
            try writer.removeItem(at: thumbnailURL)
        } catch {
            logger.debug("Thumbnail cleanup skipped for \(drawingID): \(error.localizedDescription)")
        }
    }

    /// Lists all drawing IDs for a note.
    ///
    /// - Throws: Propagates file system errors (except when the assets folder does not exist).
    public func listDrawings(for noteURL: URL) throws -> [String] {
        let assetsFolder = assetsURL(for: noteURL)

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: assetsFolder,
                includingPropertiesForKeys: nil
            )
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // Assets folder does not exist → no drawings present
            return []
        }

        return contents
            .filter { $0.pathExtension == "drawing" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Generates the Markdown embed string for a drawing.
    public func markdownEmbed(for drawingID: String) -> String {
        "![[assets/\(drawingID).drawing]]"
    }

    /// Generates a new unique drawing ID.
    public func generateDrawingID() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return "drawing-\(timestamp)-\(suffix)"
    }

    // MARK: - Private

    private func assetsURL(for noteURL: URL) -> URL {
        noteURL.deletingLastPathComponent().appending(path: "assets")
    }

    private func saveThumbnail(drawing: PKDrawing, to url: URL, maxSize: CGFloat = 800) throws {
        guard !drawing.bounds.isEmpty,
              drawing.bounds.width > 0,
              drawing.bounds.height > 0 else {
            throw DrawingStorageError.emptyDrawing
        }

        let bounds = drawing.bounds
        let scale = min(maxSize / bounds.width, maxSize / bounds.height, 2.0)
        let image = drawing.image(from: bounds, scale: scale)

        #if canImport(UIKit)
        guard let pngData = image.pngData() else {
            throw DrawingStorageError.thumbnailConversionFailed
        }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DrawingStorageError.thumbnailConversionFailed
        }
        #endif
        try writer.write(pngData, to: url)
    }
}

// MARK: - Errors

public enum DrawingStorageError: LocalizedError, Sendable {
    case emptyDrawing
    case thumbnailConversionFailed

    public var errorDescription: String? {
        switch self {
        case .emptyDrawing:
            String(localized: "Drawing is empty, cannot generate thumbnail", bundle: .module)
        case .thumbnailConversionFailed:
            String(localized: "Failed to convert drawing to PNG thumbnail", bundle: .module)
        }
    }
}
#endif
