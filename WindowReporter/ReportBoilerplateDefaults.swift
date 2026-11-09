//
//  ReportBoilerplateDefaults.swift
//  WindowReporter
//
//  Team boilerplate overrides from TeamCustomizationCache (PDF / DOCX fallbacks).
//

import Foundation

enum ReportBoilerplateDefaults {
    static func text(for key: String) -> String? {
        if let cached = TeamCustomizationCache.reportBoilerplate(),
           let val = cached[key], !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val
        }
        return nil
    }
}
