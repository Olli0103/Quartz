#if canImport(PencilKit)
import Foundation
import PencilKit
import os
#if canImport(AppKit)
import AppKit
#endif

/// Service für das Speichern und Laden von PencilKit-Zeichnungen.
///
/// Zeichnungen werden als `.drawing` Dateien im `assets/` Ordner
/// neben der zugehörigen Notiz gespeichert. Im Markdown werden sie
/// als `![[drawing-id.drawing]]` eingebettet.
public actor DrawingStorageService {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.quartz", category: "DrawingStorage")

    public init() {}

    /// Speichert eine Zeichnung als `.drawing` Datei.
    ///
    /// - Parameters:
    ///   - drawing: Die PencilKit-Zeichnung
    ///   - drawingID: Eindeutige ID der Zeichnung
    ///   - noteURL: URL der zugehörigen Notiz
    /// - Returns: Relativer Pfad zur Zeichnungsdatei (für Markdown-Embed)
    public func save(
        drawing: PKDrawing,
        drawingID: String,
        noteURL: URL
    ) throws -> String {
        let assetsFolder = assetsURL(for: noteURL)
        try fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)

        let fileName = "\(drawingID).drawing"
        let fileURL = assetsFolder.appending(path: fileName)

        let data = drawing.dataRepresentation()
        try data.write(to: fileURL, options: .atomic)

        // Thumbnail als PNG speichern
        let thumbnailURL = assetsFolder.appending(path: "\(drawingID).png")
        try saveThumbnail(drawing: drawing, to: thumbnailURL)

        return "assets/\(fileName)"
    }

    /// Lädt eine Zeichnung aus einer `.drawing` Datei.
    public func load(drawingID: String, noteURL: URL) throws -> PKDrawing {
        let assetsFolder = assetsURL(for: noteURL)
        let fileURL = assetsFolder.appending(path: "\(drawingID).drawing")

        let data = try Data(contentsOf: fileURL)
        return try PKDrawing(data: data)
    }

    /// Löscht eine Zeichnung und ihren Thumbnail.
    public func delete(drawingID: String, noteURL: URL) throws {
        let assetsFolder = assetsURL(for: noteURL)

        let drawingURL = assetsFolder.appending(path: "\(drawingID).drawing")
        let thumbnailURL = assetsFolder.appending(path: "\(drawingID).png")

        try fileManager.removeItem(at: drawingURL)
        // Thumbnail deletion is best-effort since the drawing file is primary
        do {
            try fileManager.removeItem(at: thumbnailURL)
        } catch {
            logger.debug("Thumbnail cleanup skipped for \(drawingID): \(error.localizedDescription)")
        }
    }

    /// Listet alle Zeichnungs-IDs für eine Notiz auf.
    ///
    /// - Throws: Propagiert Dateisystem-Fehler (außer wenn der assets-Ordner nicht existiert).
    public func listDrawings(for noteURL: URL) throws -> [String] {
        let assetsFolder = assetsURL(for: noteURL)

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: assetsFolder,
                includingPropertiesForKeys: nil
            )
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // Assets-Ordner existiert nicht → keine Zeichnungen vorhanden
            return []
        }

        return contents
            .filter { $0.pathExtension == "drawing" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Generiert den Markdown-Embed-String für eine Zeichnung.
    public func markdownEmbed(for drawingID: String) -> String {
        "![[assets/\(drawingID).drawing]]"
    }

    private static let drawingIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Generiert eine neue eindeutige Drawing-ID.
    public func generateDrawingID() -> String {
        let timestamp = Self.drawingIDFormatter.string(from: Date())
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return "drawing-\(timestamp)-\(suffix)"
    }

    // MARK: - Private

    private func assetsURL(for noteURL: URL) -> URL {
        noteURL.deletingLastPathComponent().appending(path: "assets")
    }

    private func saveThumbnail(drawing: PKDrawing, to url: URL, maxSize: CGFloat = 800) throws {
        guard !drawing.bounds.isEmpty else { return }

        let bounds = drawing.bounds
        let scale = min(maxSize / bounds.width, maxSize / bounds.height, 2.0)
        let image = drawing.image(from: bounds, scale: scale)

        #if canImport(UIKit)
        guard let pngData = image.pngData() else { return }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        #endif
        try pngData.write(to: url, options: .atomic)
    }
}
#endif
