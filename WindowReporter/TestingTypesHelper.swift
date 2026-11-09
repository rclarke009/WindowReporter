//
//  TestingTypesHelper.swift
//  WindowReporter
//
//  Resolves enabled testing type ids and display names (team cache + built-ins).
//

import Foundation
import CoreData

struct TestingTypesHelper {
    static func enabledTypeIds(from job: Job) -> [String] {
        guard let raw = job.enabledTestingTypeIds?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return [TestingTypeId.windows.rawValue]
        }
        return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func displayName(for typeId: String, job: Job? = nil) -> String {
        if typeId.isEmpty { return "" }
        if let cached = TeamCustomizationCache.testingTypes(),
           let match = cached.first(where: { $0.id == typeId }) {
            return match.displayName
        }
        if let job = job,
           let s = job.testingTypeDisplayNamesByIdJSON, !s.isEmpty,
           let d = s.data(using: .utf8),
           let snap = try? JSONDecoder().decode([String: String].self, from: d),
           let n = snap[typeId]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            return n
        }
        return fallbackDisplayNameWhenNoTeamRow(for: typeId)
    }

    static func fallbackDisplayNameWhenNoTeamRow(for typeId: String) -> String {
        if let known = TestingTypeId(rawValue: typeId) {
            return known.defaultDisplayName
        }
        return typeId.prefix(1).uppercased() + typeId.dropFirst()
    }

    static func isWindows(_ typeId: String) -> Bool {
        typeId == TestingTypeId.windows.rawValue
    }
}

/// Per-job id → display name snapshot (lives in `Job.testingTypeDisplayNamesByIdJSON`).
enum JobTestingTypeDisplayNameSnapshot {
    private static func readMap(_ job: Job) -> [String: String] {
        guard let s = job.testingTypeDisplayNamesByIdJSON, !s.isEmpty,
              let d = s.data(using: .utf8),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    private static func writeMap(_ map: [String: String], to job: Job) {
        if map.isEmpty {
            job.testingTypeDisplayNamesByIdJSON = nil
        } else if let data = try? JSONEncoder().encode(map),
                  let str = String(data: data, encoding: .utf8) {
            job.testingTypeDisplayNamesByIdJSON = str
        }
    }

    static func merge(into job: Job, enabledTypeIds: [String]) {
        let previous = readMap(job)
        let cache = TeamCustomizationCache.testingTypes()
        var next: [String: String] = [:]
        let enabledSet = Set(enabledTypeIds)
        for id in enabledTypeIds where enabledSet.contains(id) {
            let fromCache = cache?.first(where: { $0.id == id })?.displayName
            let name: String
            if let c = fromCache?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                name = c
            } else if let p = previous[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                name = p
            } else {
                name = TestingTypesHelper.fallbackDisplayNameWhenNoTeamRow(for: id)
            }
            next[id] = name
        }
        writeMap(next, to: job)
    }
}
