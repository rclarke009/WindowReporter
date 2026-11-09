//
//  SupabaseManager.swift
//  WindowReporter
//

import AppKit
import Combine
import Foundation
import Supabase

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    static let windowTypeImagesBucket = "window-type-images"

    let client: SupabaseClient
    let isConfigured: Bool

    @Published var session: Session?
    @Published var profile: AppProfile?
    @Published var organization: AppOrganization?
    @Published var isLoading = false
    @Published var configurationError: String?

    var isAuthenticated: Bool { session != nil }
    var isAdmin: Bool { profile?.role == "admin" }
    var organizationId: UUID? { profile?.organizationId }

    /// Ensures a parseable URL with a real host; avoids silent network failures from typos in plist.
    private static func isValidSupabaseHTTPURL(_ url: URL?) -> Bool {
        guard let url, let host = url.host, !host.isEmpty else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" { return true }
        // Local Supabase CLI often uses http on loopback
        if scheme == "http", ["localhost", "127.0.0.1"].contains(host) { return true }
        return false
    }

    private init() {
        let rawURL = ConfigManager.shared.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ConfigManager.shared.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredURL = URL(string: rawURL)
        // Wrong project ref in the hostname often shows up as "cannot find host" in the app — validate shape early.
        let isValidConfig = !rawURL.isEmpty && !key.isEmpty
            && Self.isValidSupabaseHTTPURL(configuredURL)

        self.isConfigured = isValidConfig
        if !isValidConfig {
            self.configurationError = "Supabase is not configured. Set SupabaseURL to the full https URL (e.g. https://xxxxx.supabase.co) and SupabaseAnonKey from the Supabase dashboard (Settings → API)."
            print("MYDEBUG →", "SupabaseManager running in disabled mode (missing/invalid Config.plist values)")
        }

        let url = configuredURL ?? URL(string: "https://invalid.local")!
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: key)

        if isValidConfig {
            Task { await listenForAuthChanges() }
        }
    }

    private func listenForAuthChanges() async {
        for await state in client.auth.authStateChanges {
            if [.initialSession, .signedIn, .signedOut].contains(state.event) {
                self.session = state.session
                if state.session != nil {
                    await loadProfile()
                } else {
                    self.profile = nil
                    self.organization = nil
                }
            }
        }
    }

    private func ensureConfigured() throws {
        guard isConfigured else { throw SupabaseManagerError.notConfigured }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        try ensureConfigured()
        _ = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
    }

    func signIn(email: String, password: String) async throws {
        try ensureConfigured()
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try ensureConfigured()
        try await client.auth.signOut()
        self.session = nil
        self.profile = nil
        self.organization = nil
    }

    func loadProfile() async {
        guard isConfigured else { return }
        guard let userId = session?.user.id else { return }
        do {
            let row: AppProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            self.profile = row
            if let orgId = row.organizationId {
                await loadOrganization(orgId)
            }
        } catch {
            print("MYDEBUG →", "Failed to load profile: \(error)")
        }
    }

    private func loadOrganization(_ orgId: UUID) async {
        guard isConfigured else { return }
        do {
            let row: AppOrganization = try await client
                .from("organizations")
                .select()
                .eq("id", value: orgId.uuidString)
                .single()
                .execute()
                .value
            self.organization = row
            TeamCustomizationCache.saveOrganizationId(orgId)
        } catch {
            print("MYDEBUG →", "Failed to load org: \(error)")
        }
    }

    func createOrganization(name: String) async throws -> AppOrganization {
        try ensureConfigured()
        guard session?.user.id != nil else {
            throw SupabaseManagerError.notAuthenticated
        }

        let newOrg: AppOrganization = try await client
            .rpc("create_organization_for_user", params: ["org_name": name])
            .execute()
            .value

        self.organization = newOrg
        await loadProfile()
        return newOrg
    }

    func joinTeam(code: String) async throws {
        try ensureConfigured()
        guard let userId = session?.user.id else {
            throw SupabaseManagerError.notAuthenticated
        }

        let orgs: [AppOrganization] = try await client
            .from("organizations")
            .select()
            .eq("team_code", value: code.lowercased())
            .execute()
            .value

        guard let org = orgs.first else {
            throw SupabaseManagerError.invalidTeamCode
        }

        try await client
            .from("profiles")
            .update([
                "organization_id": org.id.uuidString,
                "role": "member"
            ])
            .eq("id", value: userId.uuidString)
            .execute()

        self.organization = org
        await loadProfile()
    }

    nonisolated static func sanitizeWindowTypeStorageSlug(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var slug = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if slug.isEmpty { slug = "type" }
        if slug.count > 120 { slug = String(slug.prefix(120)) }
        return slug
    }

    static func normalizedJPEGData(from data: Data, quality: CGFloat = 0.7) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    func uploadWindowTypeImage(organizationId: UUID, typeName: String, imageData: Data) async throws -> String {
        try ensureConfigured()
        let jpeg = Self.normalizedJPEGData(from: imageData) ?? imageData
        let slug = Self.sanitizeWindowTypeStorageSlug(typeName)
        let path = "\(organizationId.uuidString)/\(slug).jpg"
        try await client.storage
            .from(Self.windowTypeImagesBucket)
            .upload(
                path,
                data: jpeg,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        return path
    }

    func downloadWindowTypeImage(path: String) async throws -> Data {
        try ensureConfigured()
        return try await client.storage
            .from(Self.windowTypeImagesBucket)
            .download(path: path)
    }

    func deleteWindowTypeImage(path: String) async throws {
        try ensureConfigured()
        try await client.storage
            .from(Self.windowTypeImagesBucket)
            .remove(paths: [path])
    }
}

struct AppProfile: Codable {
    let id: UUID
    let organizationId: UUID?
    let role: String
    let displayName: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case role
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct AppOrganization: Codable {
    let id: UUID
    let name: String
    let teamCode: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case teamCode = "team_code"
        case createdAt = "created_at"
    }
}

enum SupabaseManagerError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case invalidTeamCode
    case noOrganization

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured for this build. Add SupabaseURL and SupabaseAnonKey to Config.plist."
        case .notAuthenticated: return "You must be signed in to do this."
        case .invalidTeamCode: return "No team found with that code. Check with your admin."
        case .noOrganization: return "You're not part of a team yet."
        }
    }
}
