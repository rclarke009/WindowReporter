//
//  PhotoNoteCategoriesTransferService.swift
//  WindowReporter
//
//  Export/import package model and ZIP exporter for photo note categories/captions.
//

import Foundation
import ZIPFoundation

struct PhotoNoteCategoriesPackage: Codable {
    let version: String
    let exportedAt: Double
    let exportedBy: String?
    let photoNoteCategories: PhotoNoteCategoriesPayload
}

final class PhotoNoteCategoriesPackageExporter {
    private let payload: PhotoNoteCategoriesPayload
    private let exportedBy: String?
    private let fileManager = FileManager.default

    init(payload: PhotoNoteCategoriesPayload, exportedBy: String?) {
        self.payload = payload
        self.exportedBy = exportedBy
    }

    func export() async throws -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = documentsDirectory.appendingPathComponent("exports")
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let packageName = "photo-note-categories-\(timestamp)"

        let packageDirectory = exportDirectory.appendingPathComponent(packageName)
        try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let package = PhotoNoteCategoriesPackage(
            version: "1.0",
            exportedAt: Date().timeIntervalSince1970,
            exportedBy: exportedBy,
            photoNoteCategories: payload
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(package)
        let jsonURL = packageDirectory.appendingPathComponent("photo-note-categories-package.json")
        try jsonData.write(to: jsonURL)

        let zipURL = exportDirectory.appendingPathComponent("\(packageName).zip")
        try await createZIPArchive(from: packageDirectory, to: zipURL)
        return zipURL
    }

    private func createZIPArchive(from sourceDir: URL, to destinationURL: URL) async throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let archive = try Archive(url: destinationURL, accessMode: .create)

        let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                var relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
                relativePath = relativePath.replacingOccurrences(of: "\\", with: "/")
                let fileData = try Data(contentsOf: fileURL)

                try archive.addEntry(with: relativePath, type: .file, uncompressedSize: UInt32(fileData.count), compressionMethod: .none) { position, size in
                    return fileData.subdata(in: position..<position + size)
                }
            }
        }
    }
}

final class PhotoNoteCategoriesCSVExporter {
    private let payload: PhotoNoteCategoriesPayload
    private let fileManager = FileManager.default

    init(payload: PhotoNoteCategoriesPayload) {
        self.payload = payload
    }

    func export() throws -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = documentsDirectory.appendingPathComponent("exports")
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let csvURL = exportDirectory.appendingPathComponent("photo-note-categories-\(timestamp).csv")

        let sortedPhotoTypes = payload.keys.sorted()
        var csvRows: [String] = ["Photo Type,Category,Caption Index,Caption"]

        for photoType in sortedPhotoTypes {
            guard let categories = payload[photoType] else { continue }
            for category in categories {
                if category.options.isEmpty {
                    csvRows.append([
                        csvCell(photoType),
                        csvCell(category.name),
                        "1",
                        csvCell("")
                    ].joined(separator: ","))
                    continue
                }

                for (index, caption) in category.options.enumerated() {
                    csvRows.append([
                        csvCell(photoType),
                        csvCell(category.name),
                        String(index + 1),
                        csvCell(caption)
                    ].joined(separator: ","))
                }
            }
        }

        let csvContent = csvRows.joined(separator: "\n") + "\n"
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        return csvURL
    }

    private func csvCell(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
