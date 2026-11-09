//
//  TeamCustomizationCache.swift
//  WindowReporter
//
//  Local cache for team customizations (macOS). Application Support + UserDefaults.
//

import AppKit
import Foundation

enum TeamCustomizationCache {
    private static let prefix = "teamCustomization_"
    private static let windowTypeImagesSubfolder = "window-type-images"

    enum Key: String {
        case photoCategories
        case testingTypes
        case windowTypes
        case windowTypesByScope
        case reportBoilerplate
        case testingProcedures
        case lastSyncDate
        case organizationId
        case windowTypeImageLocalPaths
        case windowTypeImageRemotePaths
    }

    static func save<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: prefix + key.rawValue)
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = UserDefaults.standard.data(forKey: prefix + key.rawValue),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        return decoded
    }

    static func remove(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: prefix + key.rawValue)
    }

    static func photoCategories() -> PhotoNoteCategoriesPayload? {
        load(PhotoNoteCategoriesPayload.self, for: .photoCategories)
    }

    static func savePhotoCategories(_ payload: PhotoNoteCategoriesPayload) {
        save(payload, for: .photoCategories)
    }

    static func testingTypes() -> [CachedTestingType]? {
        load([CachedTestingType].self, for: .testingTypes)
    }

    static func saveTestingTypes(_ types: [CachedTestingType]) {
        save(types, for: .testingTypes)
    }

    static func windowTypes() -> [String]? {
        if let scope = windowTypesByScope() {
            let u = scope.unionTypeNames()
            return u.isEmpty ? nil : u
        }
        return load([String].self, for: .windowTypes)
    }

    static func saveWindowTypes(_ types: [String]) {
        save(types, for: .windowTypes)
    }

    static func windowTypesByScope() -> CachedWindowTypesByScope? {
        if let scoped = load(CachedWindowTypesByScope.self, for: .windowTypesByScope) {
            return scoped
        }
        if let flat = load([String].self, for: .windowTypes), !flat.isEmpty {
            return CachedWindowTypesByScope(byTestingTypeId: [TestingTypeId.windows.rawValue: flat])
        }
        return nil
    }

    static func saveWindowTypesByScope(_ scope: CachedWindowTypesByScope) {
        save(scope, for: .windowTypesByScope)
        save(scope.unionTypeNames(), for: .windowTypes)
    }

    static func windowTypeImageLocalPaths() -> [String: String]? {
        load([String: String].self, for: .windowTypeImageLocalPaths)
    }

    static func saveWindowTypeImageLocalPaths(_ paths: [String: String]) {
        save(paths, for: .windowTypeImageLocalPaths)
    }

    static func windowTypeImageRemotePaths() -> [String: String]? {
        load([String: String].self, for: .windowTypeImageRemotePaths)
    }

    static func saveWindowTypeImageRemotePaths(_ paths: [String: String]) {
        save(paths, for: .windowTypeImageRemotePaths)
    }

    static func windowTypeImagesRootDirectory(organizationId: UUID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "WindowReporter"
        return appSupport
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent(windowTypeImagesSubfolder, isDirectory: true)
            .appendingPathComponent(organizationId.uuidString, isDirectory: true)
    }

    @discardableResult
    static func saveWindowTypeImageData(_ data: Data, for typeName: String, organizationId: UUID) throws -> String {
        let dir = windowTypeImagesRootDirectory(organizationId: organizationId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = SupabaseManager.sanitizeWindowTypeStorageSlug(typeName)
        let fileURL = dir.appendingPathComponent("\(slug).jpg")
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    static func windowTypeImage(for typeName: String) -> NSImage? {
        guard cachedOrganizationId() != nil else { return nil }
        guard let pathMap = windowTypeImageLocalPaths(),
              let localPath = pathMap[typeName],
              FileManager.default.fileExists(atPath: localPath) else { return nil }
        return NSImage(contentsOf: URL(fileURLWithPath: localPath))
    }

    static func removeWindowTypeImageFiles(organizationId: UUID) {
        let dir = windowTypeImagesRootDirectory(organizationId: organizationId)
        try? FileManager.default.removeItem(at: dir)
    }

    static func reportBoilerplate() -> [String: String]? {
        load([String: String].self, for: .reportBoilerplate)
    }

    static func saveReportBoilerplate(_ fields: [String: String]) {
        save(fields, for: .reportBoilerplate)
    }

    static func testingProcedures() -> [String: CachedProcedureConfig]? {
        load([String: CachedProcedureConfig].self, for: .testingProcedures)
    }

    static func saveTestingProcedures(_ configs: [String: CachedProcedureConfig]) {
        save(configs, for: .testingProcedures)
    }

    static func saveLastSyncDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: prefix + Key.lastSyncDate.rawValue)
    }

    static func lastSyncDate() -> Date? {
        UserDefaults.standard.object(forKey: prefix + Key.lastSyncDate.rawValue) as? Date
    }

    static func saveOrganizationId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: prefix + Key.organizationId.rawValue)
    }

    static func cachedOrganizationId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: prefix + Key.organizationId.rawValue) else { return nil }
        return UUID(uuidString: str)
    }

    static func clearAll() {
        if let org = cachedOrganizationId() {
            removeWindowTypeImageFiles(organizationId: org)
        }
        for key in Key.allCases {
            UserDefaults.standard.removeObject(forKey: prefix + key.rawValue)
        }
        print("MYDEBUG →", "TeamCustomizationCache cleared (ReportWriter)")
    }
}

extension TeamCustomizationCache.Key: CaseIterable {}

struct CachedTestingType: Codable, Identifiable {
    let id: String
    var displayName: String
    var enabled: Bool
}

struct CachedWindowTypesByScope: Codable, Equatable {
    var byTestingTypeId: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case byTestingTypeId = "by_testing_type_id"
    }

    init(byTestingTypeId: [String: [String]] = [:]) {
        self.byTestingTypeId = byTestingTypeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byTestingTypeId = try c.decodeIfPresent([String: [String]].self, forKey: .byTestingTypeId) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(byTestingTypeId, forKey: .byTestingTypeId)
    }

    func unionTypeNames() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in byTestingTypeId.keys.sorted() {
            for t in byTestingTypeId[id] ?? [] where !t.isEmpty {
                if seen.insert(t).inserted { result.append(t) }
            }
        }
        return result
    }

    func orderedTypeNames(forTestingTypeId typeId: String) -> [String] {
        (byTestingTypeId[typeId] ?? []).filter { !$0.isEmpty }
    }

    mutating func setListForTestingTypeId(_ typeId: String, names: [String]) {
        byTestingTypeId[typeId] = names
    }
}

struct CachedProcedureStep: Codable, Identifiable {
    let id: String
    var label: String
    var fieldType: String
    var options: [String]?
    var enabled: Bool
    var isBuiltIn: Bool
}

struct CachedProcedureConfig: Codable {
    var steps: [CachedProcedureStep]
}
