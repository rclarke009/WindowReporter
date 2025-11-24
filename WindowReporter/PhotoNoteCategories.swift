//
//  PhotoNoteCategories.swift
//  WindowReporter
//
//  Created for photo note categorization
//

import Foundation
import SwiftUI

enum PhotoType: String, CaseIterable {
    case exterior = "Exterior"
    case interior = "Interior"
    case leak = "Leak"
    
    var icon: String {
        switch self {
        case .exterior:
            return "house"
        case .interior:
            return "door.left.hand.open"
        case .leak:
            return "drop"
        }
    }
    
    var color: Color {
        switch self {
        case .exterior:
            return .green
        case .interior:
            return .yellow
        case .leak:
            return .blue
        }
    }
}

extension PhotoType: Identifiable {
    var id: String { rawValue }
}

struct PhotoNoteCategory {
    let name: String
    let options: [String]
}

struct PhotoNoteCategories {
    // Exterior photo categories
    static let exteriorCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Stucco Issues",
            options: [
                "Small separation in the stucco near the window frame.",
                "Close-up of crack shows elastomeric stretching of the surface paint."
            ]
        ),
        PhotoNoteCategory(
            name: "Frame and Sill Issues",
            options: [
                "Frame separation from wall.",
                "Sill damage is visible here."
            ]
        ),
        PhotoNoteCategory(
            name: "Weather Stripping",
            options: [
                "Weather stripping damaged or missing. -other",
                "Weather stripping not properly seated. -other"
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: [] // Empty array indicates custom text input
        )
    ]
    
    // Interior photo categories
    static let interiorCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Overview Photo",
            options: [
                "Interior view of the window."
            ]
        ),
        PhotoNoteCategory(
            name: "Drywall Cracks",
            options: [
                "Crack between frame and drywall due to cyclical wind pressures.",
                "Crack in drywall due to cyclical wind pressures.",
                "Recent crack at drywall due to cyclical wind pressures.",
                "Close-up of crack in drywall.",
                "Water stain is visible here.",
                "This crack is an indication of cyclical pressure causing movement.",
                "Cracking in drywall near frame; drywall cracks show signs of shear stress."
            ]
        ),
        PhotoNoteCategory(
            name: "Ceiling and Wall Connections",
            options: [
                "Cracks at ceiling to wall connection.",
                "Separation at ceiling to wall joint near window."
            ]
        ),
        PhotoNoteCategory(
            name: "Windowsill Separations",
            options: [
                "Separation at windowsill and wall.",
                "Some separation between windowsill and drywall."
            ]
        ),
        PhotoNoteCategory(
            name: "Frame and Trim Issues",
            options: [
                "Interior frame separation from wall.",
                "Recent separation ofthe window frame and the drywall."
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: [] // Empty array indicates custom text input
        )
    ]
    
    // Leak photo categories
    static let leakCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Active Leak",
            options: [
                "Active water leak visible.",
                "Water staining indicating leak.",
                "Moisture present at leak location."
            ]
        ),
        PhotoNoteCategory(
            name: "Leak Location",
            options: [
                "Leak at corner of window frame.",
                "Water entered between the window frame and wall.",
                "Leak at bottom mullion."
            ]
        ),
        PhotoNoteCategory(
            name: "Water Damage",
            options: [
                "Water damage from leak.",
                "Water damage from recent leak.",
                "Staining from previous leak."
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: [] // Empty array indicates custom text input
        )
    ]
    
    // Legacy support - returns exterior categories for backward compatibility
    static var categories: [PhotoNoteCategory] {
        return exteriorCategories
    }
    
    // Get categories for a specific photo type
    static func getCategories(for photoType: PhotoType) -> [PhotoNoteCategory] {
        switch photoType {
        case .exterior:
            return exteriorCategories
        case .interior:
            return interiorCategories
        case .leak:
            return leakCategories
        }
    }
    
    static func getCategory(byName name: String, for photoType: PhotoType) -> PhotoNoteCategory? {
        let categories = getCategories(for: photoType)
        return categories.first { $0.name == name }
    }
    
    // Legacy support
    static func getCategory(byName name: String) -> PhotoNoteCategory? {
        return categories.first { $0.name == name }
    }
    
    static func getAllCategoryNames(for photoType: PhotoType) -> [String] {
        return getCategories(for: photoType).map { $0.name }
    }
    
    // Legacy support
    static func getAllCategoryNames() -> [String] {
        return categories.map { $0.name }
    }
}

