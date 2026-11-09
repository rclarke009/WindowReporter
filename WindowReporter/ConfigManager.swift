//
//  ConfigManager.swift
//  WindowReporter
//

import Foundation

class ConfigManager {
    static let shared = ConfigManager()

    private var config: [String: Any] = [:]

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("MYDEBUG →", "Config.plist not found or invalid (ReportWriter)")
            return
        }
        config = plist
    }

    var supabaseURL: String {
        config["SupabaseURL"] as? String ?? ""
    }

    var supabaseAnonKey: String {
        config["SupabaseAnonKey"] as? String ?? ""
    }

    var isSupabaseConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
