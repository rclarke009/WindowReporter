//
//  TeamTestingTypesOrdering.swift
//  WindowReporter
//
//  Resolves team testing-type list order for Settings/Edit Job and
//  comma-joined `enabledTestingTypeIds` (field app and PDFs follow string order).
//

import Foundation
import CoreData

enum TeamTestingTypesOrdering {
    private static func builtInRows() -> [(id: String, name: String)] {
        TestingTypeId.allCases.map { ($0.rawValue, $0.defaultDisplayName) }
    }

    private static func displayNameForId(_ id: String, cache: [CachedTestingType]?, job: Job?) -> String {
        if let t = cache?.first(where: { $0.id == id }) { return t.displayName }
        return TestingTypesHelper.displayName(for: id, job: job)
    }

    private static func rowsFromBuiltInWithOrphans(currentSelection: Set<String>, job: Job?) -> [(id: String, name: String)] {
        var result = builtInRows()
        let seen = Set(result.map(\.id))
        for id in currentSelection.subtracting(seen).sorted() {
            result.append((id, displayNameForId(id, cache: nil, job: job)))
        }
        return result
    }

    /// Rows for Settings / Edit Job toggles: team order for enabled types, then any selected id not in that list.
    static func rowsForToggles(currentSelection: Set<String>, job: Job? = nil) -> [(id: String, name: String)] {
        guard let cached = TeamCustomizationCache.testingTypes(), !cached.isEmpty else {
            return rowsFromBuiltInWithOrphans(currentSelection: currentSelection, job: job)
        }
        var result: [(id: String, name: String)] = []
        var seen = Set<String>()
        for t in cached where t.enabled {
            result.append((t.id, t.displayName))
            seen.insert(t.id)
        }
        for id in currentSelection.subtracting(seen).sorted() {
            result.append((id, displayNameForId(id, cache: cached, job: job)))
        }
        return result
    }

    /// Comma-separated ids in team preference order; falls back to `"windows"` when none enabled.
    static func commaJoinedPreservingOrder(enabledIds: Set<String>) -> String {
        if enabledIds.isEmpty { return "windows" }
        let rows = rowsForToggles(currentSelection: enabledIds)
        var ordered: [String] = []
        var seen = Set<String>()
        for (id, _) in rows where enabledIds.contains(id) {
            ordered.append(id)
            seen.insert(id)
        }
        for id in enabledIds.subtracting(seen).sorted() {
            ordered.append(id)
        }
        return ordered.joined(separator: ",")
    }
}
