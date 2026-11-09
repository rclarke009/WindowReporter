//
//  PhotoNoteCategoriesStore.swift
//  WindowReporter
//
//  Persists editable photo note categories and provides payload for full job package export.
//

import Foundation
import Combine

// MARK: - Codable payload (package + JSON file; same schema as WindowTest)

struct PhotoNoteCategoryItem: Codable, Equatable {
    var name: String
    var options: [String]
}

/// Key = PhotoType.rawValue (e.g. "Interior Close-up & Damage")
typealias PhotoNoteCategoriesPayload = [String: [PhotoNoteCategoryItem]]

// MARK: - Store

final class PhotoNoteCategoriesStore: ObservableObject {
    static let shared = PhotoNoteCategoriesStore()
    
    /// In-memory config: photoType.rawValue -> editable categories
    @Published private(set) var payload: PhotoNoteCategoriesPayload = [:]
    
    private let fileManager = FileManager.default
    private let fileName = "PhotoNoteCategories.json"
    
    private var fileURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowReporter", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    
    private init() {
        load()
    }
    
    /// For export: current config as payload (empty if never customized)
    func exportPayload() -> PhotoNoteCategoriesPayload? {
        payload.isEmpty ? nil : payload
    }
    
    /// Replace entire config (e.g. from editor or reset to defaults)
    func setPayload(_ newPayload: PhotoNoteCategoriesPayload) {
        payload = newPayload
        save()
    }
    
    /// Update categories for one photo type
    func setCategories(_ items: [PhotoNoteCategoryItem], forPhotoTypeRaw raw: String) {
        if items.isEmpty {
            payload.removeValue(forKey: raw)
        } else {
            payload[raw] = items
        }
        save()
    }
    
    /// Categories for one photo type (from store or built-in)
    func categories(forPhotoTypeRaw raw: String) -> [PhotoNoteCategoryItem] {
        if let stored = payload[raw], !stored.isEmpty {
            return stored
        }
        guard let photoType = PhotoType(rawValue: raw) else { return [] }
        return PhotoNoteCategories.getCategories(for: photoType).map { cat in
            PhotoNoteCategoryItem(name: cat.name, options: cat.options)
        }
    }
    
    /// Reset to built-in defaults and persist
    func resetToDefaults() {
        var newPayload: PhotoNoteCategoriesPayload = [:]
        for photoType in PhotoType.allCases {
            let cats = PhotoNoteCategories.getCategories(for: photoType)
            newPayload[photoType.rawValue] = cats.map { PhotoNoteCategoryItem(name: $0.name, options: $0.options) }
        }
        payload = newPayload
        save()
        print("MYDEBUG →", "PhotoNoteCategoriesStore reset to defaults")
    }
    
    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PhotoNoteCategoriesPayload.self, from: data) else {
            seedFromBuiltIn()
            return
        }
        payload = decoded
        print("MYDEBUG →", "PhotoNoteCategoriesStore loaded from file, \(decoded.count) photo types")
    }
    
    private func seedFromBuiltIn() {
        resetToDefaults()
    }
    
    private func save() {
        guard !payload.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL)
        } catch {
            print("MYDEBUG →", "PhotoNoteCategoriesStore save failed: \(error)")
        }
    }
}
