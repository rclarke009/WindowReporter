//
//  CustomizationSyncService.swift
//  WindowReporter
//
//  Fetches team customizations from Supabase and writes them into TeamCustomizationCache.
//  Also provides upload helpers for admin editors.
//

import Foundation
import Supabase

enum CustomizationSyncService {

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Full sync (pull everything for the org)

    static func syncAll(organizationId: UUID) async {
        async let cats: () = syncPhotoCategories(organizationId: organizationId)
        async let types: () = syncTestingTypes(organizationId: organizationId)
        async let win: () = syncWindowTypes(organizationId: organizationId)
        async let boiler: () = syncReportBoilerplate(organizationId: organizationId)
        async let procs: () = syncTestingProcedures(organizationId: organizationId)
        _ = await (cats, types, win, boiler, procs)
        TeamCustomizationCache.saveOrganizationId(organizationId)
        TeamCustomizationCache.saveLastSyncDate(Date())
        print("MYDEBUG →", "Full customization sync complete for org \(organizationId)")
        await MainActor.run {
            NotificationCenter.default.post(name: .teamCustomizationsDidSync, object: nil)
        }
    }

    // MARK: - Photo categories

    static func syncPhotoCategories(organizationId: UUID) async {
        do {
            let rows: [PhotoCategoryRow] = try await client
                .from("photo_categories")
                .select()
                .eq("organization_id", value: organizationId.uuidString)
                .execute()
                .value
            var payload: PhotoNoteCategoriesPayload = [:]
            for row in rows {
                payload[row.photoType] = row.categories
            }
            if !payload.isEmpty {
                TeamCustomizationCache.savePhotoCategories(payload)
            }
        } catch {
            print("MYDEBUG →", "syncPhotoCategories error: \(error)")
        }
    }

    static func upsertPhotoCategories(organizationId: UUID, photoType: String, categories: [PhotoNoteCategoryItem]) async throws {
        let row = PhotoCategoryUpsert(organizationId: organizationId, photoType: photoType, categories: categories)
        try await client
            .from("photo_categories")
            .upsert(row, onConflict: "organization_id,photo_type")
            .execute()
    }

    // MARK: - Testing types

    static func syncTestingTypes(organizationId: UUID) async {
        do {
            let rows: [TestingTypeRow] = try await client
                .from("testing_types")
                .select()
                .eq("organization_id", value: organizationId.uuidString)
                .execute()
                .value
            if let row = rows.first {
                TeamCustomizationCache.saveTestingTypes(row.types)
            }
        } catch {
            print("MYDEBUG →", "syncTestingTypes error: \(error)")
        }
    }

    static func upsertTestingTypes(organizationId: UUID, types: [CachedTestingType]) async throws {
        let row = TestingTypeUpsert(organizationId: organizationId, types: types)
        try await client
            .from("testing_types")
            .upsert(row, onConflict: "organization_id")
            .execute()
    }

    // MARK: - Window types

    static func syncWindowTypes(organizationId: UUID) async {
        do {
            let rows: [WindowTypeRow] = try await client
                .from("window_types")
                .select()
                .eq("organization_id", value: organizationId.uuidString)
                .execute()
                .value
            guard let row = rows.first else { return }
            let scope: CachedWindowTypesByScope
            if let s = row.typesByScope {
                scope = s
            } else {
                let win = TestingTypeId.windows.rawValue
                let map: [String: [String]] = row.types.isEmpty ? [:] : [win: row.types]
                scope = CachedWindowTypesByScope(byTestingTypeId: map)
            }
            TeamCustomizationCache.saveWindowTypesByScope(scope)
            let union = scope.unionTypeNames()
            if let remote = row.typeImages, !remote.isEmpty {
                TeamCustomizationCache.saveWindowTypeImageRemotePaths(remote)
                await downloadWindowTypeImages(organizationId: organizationId, remote: remote, validTypeNames: Set(union))
            } else {
                TeamCustomizationCache.saveWindowTypeImageLocalPaths([:])
                TeamCustomizationCache.saveWindowTypeImageRemotePaths([:])
                TeamCustomizationCache.removeWindowTypeImageFiles(organizationId: organizationId)
            }
        } catch {
            print("MYDEBUG →", "syncWindowTypes error: \(error)")
        }
    }

    private static func downloadWindowTypeImages(organizationId: UUID, remote: [String: String], validTypeNames: Set<String>) async {
        var local: [String: String] = [:]
        for (typeName, path) in remote where validTypeNames.contains(typeName) {
            do {
                let data = try await SupabaseManager.shared.downloadWindowTypeImage(path: path)
                let localPath = try TeamCustomizationCache.saveWindowTypeImageData(data, for: typeName, organizationId: organizationId)
                local[typeName] = localPath
            } catch {
                print("MYDEBUG →", "downloadWindowTypeImage failed for \(typeName): \(error)")
            }
        }
        TeamCustomizationCache.saveWindowTypeImageLocalPaths(local)
    }

    static func upsertWindowTypes(organizationId: UUID, scope: CachedWindowTypesByScope, typeImages: [String: String]) async throws {
        let union = scope.unionTypeNames()
        let row = WindowTypeUpsert(
            organizationId: organizationId,
            types: union,
            typeImages: typeImages,
            typesByScope: scope
        )
        try await client
            .from("window_types")
            .upsert(row, onConflict: "organization_id")
            .execute()
    }

    // MARK: - Report boilerplate

    static func syncReportBoilerplate(organizationId: UUID) async {
        do {
            let rows: [ReportBoilerplateRow] = try await client
                .from("report_boilerplate")
                .select()
                .eq("organization_id", value: organizationId.uuidString)
                .execute()
                .value
            var fields: [String: String] = [:]
            for row in rows {
                fields[row.fieldKey] = row.content
            }
            if !fields.isEmpty {
                TeamCustomizationCache.saveReportBoilerplate(fields)
            }
        } catch {
            print("MYDEBUG →", "syncReportBoilerplate error: \(error)")
        }
    }

    static func upsertReportBoilerplate(organizationId: UUID, fieldKey: String, content: String) async throws {
        let row = ReportBoilerplateUpsert(organizationId: organizationId, fieldKey: fieldKey, content: content)
        try await client
            .from("report_boilerplate")
            .upsert(row, onConflict: "organization_id,field_key")
            .execute()
    }

    // MARK: - Testing procedures

    static func syncTestingProcedures(organizationId: UUID) async {
        do {
            let rows: [TestingProcedureRow] = try await client
                .from("testing_procedures")
                .select()
                .eq("organization_id", value: organizationId.uuidString)
                .execute()
                .value
            var configs: [String: CachedProcedureConfig] = [:]
            for row in rows {
                configs[row.testingTypeId] = row.procedureConfig
            }
            if !configs.isEmpty {
                TeamCustomizationCache.saveTestingProcedures(configs)
            }
        } catch {
            print("MYDEBUG →", "syncTestingProcedures error: \(error)")
        }
    }

    static func upsertTestingProcedure(organizationId: UUID, testingTypeId: String, config: CachedProcedureConfig) async throws {
        let row = TestingProcedureUpsert(organizationId: organizationId, testingTypeId: testingTypeId, procedureConfig: config)
        try await client
            .from("testing_procedures")
            .upsert(row, onConflict: "organization_id,testing_type_id")
            .execute()
    }
}

// MARK: - Row types for decoding Supabase responses

private struct PhotoCategoryRow: Codable {
    let id: UUID
    let organizationId: UUID
    let photoType: String
    let categories: [PhotoNoteCategoryItem]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case photoType = "photo_type"
        case categories
        case updatedAt = "updated_at"
    }
}

private struct PhotoCategoryUpsert: Codable {
    let organizationId: UUID
    let photoType: String
    let categories: [PhotoNoteCategoryItem]

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case photoType = "photo_type"
        case categories
    }
}

private struct TestingTypeRow: Codable {
    let id: UUID
    let organizationId: UUID
    let types: [CachedTestingType]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case types
        case updatedAt = "updated_at"
    }
}

private struct TestingTypeUpsert: Codable {
    let organizationId: UUID
    let types: [CachedTestingType]

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case types
    }
}

private struct WindowTypeRow: Codable {
    let id: UUID
    let organizationId: UUID
    let types: [String]
    let typeImages: [String: String]?
    let typesByScope: CachedWindowTypesByScope?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case types
        case typeImages = "type_images"
        case typesByScope = "types_by_scope"
        case updatedAt = "updated_at"
    }
}

private struct WindowTypeUpsert: Codable {
    let organizationId: UUID
    let types: [String]
    let typeImages: [String: String]
    let typesByScope: CachedWindowTypesByScope

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case types
        case typeImages = "type_images"
        case typesByScope = "types_by_scope"
    }
}

private struct ReportBoilerplateRow: Codable {
    let id: UUID
    let organizationId: UUID
    let fieldKey: String
    let content: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case fieldKey = "field_key"
        case content
        case updatedAt = "updated_at"
    }
}

private struct ReportBoilerplateUpsert: Codable {
    let organizationId: UUID
    let fieldKey: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case fieldKey = "field_key"
        case content
    }
}

private struct TestingProcedureRow: Codable {
    let id: UUID
    let organizationId: UUID
    let testingTypeId: String
    let procedureConfig: CachedProcedureConfig
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case testingTypeId = "testing_type_id"
        case procedureConfig = "procedure_config"
        case updatedAt = "updated_at"
    }
}

private struct TestingProcedureUpsert: Codable {
    let organizationId: UUID
    let testingTypeId: String
    let procedureConfig: CachedProcedureConfig

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case testingTypeId = "testing_type_id"
        case procedureConfig = "procedure_config"
    }
}
