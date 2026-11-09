//
//  PhotoNoteCategories.swift
//  WindowReporter
//
//  Created for photo note categorization
//

import Foundation
import SwiftUI

enum PhotoType: String, CaseIterable {
    // Legacy types (kept for backward compatibility)
    case exterior = "Exterior"
    case interior = "Interior"
    case leak = "Leak"
    case aama = "AAMA"
    
    // New specific types
    case interiorWideView = "Interior Wide View"
    case interiorCloseup = "Interior Close-up & Damage"
    case leakCloseups = "Leak Close-ups"
    case exteriorWideView = "Exterior Wide View"
    case exteriorPhotos = "Exterior Photos"
    
    var icon: String {
        switch self {
        case .exterior, .exteriorWideView, .exteriorPhotos:
            return "house"
        case .interior, .interiorWideView:
            return "door.left.hand.open"
        case .interiorCloseup:
            return "camera.macro"
        case .leak, .leakCloseups:
            return "drop"
        case .aama:
            return "tag"
        }
    }
    
    var color: Color {
        switch self {
        case .exterior, .exteriorWideView, .exteriorPhotos:
            return .green
        case .interior, .interiorWideView:
            return Color(red: 0, green: 0.5, blue: 0.6) // Darker teal
        case .interiorCloseup:
            return .indigo
        case .leak, .leakCloseups:
            return .blue
        case .aama:
            return .indigo
        }
    }

    /// Photo types that the field app (WindowTest) uses in its UI. Use this when presenting categories for editing so users only modify captions that appear in the field app. Legacy types (Exterior, Interior, Leak) are not shown in WindowTest’s specimen flow.
    static var photoTypesUsedInFieldApp: [PhotoType] {
        [.interiorWideView, .interiorCloseup, .aama, .leakCloseups, .exteriorWideView, .exteriorPhotos]
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
                "Interior view of the window.",
                "Wide view of the room containing the specimen.",
                "Wide view of the window from the interior."
            ]
        ),
        PhotoNoteCategory(
            name: "Frame to Wall",
            options: [
                "Crack between frame and drywall due to cyclical wind pressures.",
                "Crack in drywall due to cyclical wind pressures.",
                "Recent crack at drywall due to cyclical wind pressures.",
                "This crack is an indication of cyclical pressure causing movement.",
                "Close-up of crack/separation in drywall.",
                "Cracking in drywall near frame; drywall cracks show signs of shear stress.",
                "Macro lens image shows the opening is fairly clean and free of debris.",
                "Interior frame separation from wall.",
                "Recent separation of the window frame and the drywall."

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
            name: "Windowsill Separations/???",
            options: [
                "Separation at windowsill and wall.",
                "Some separation between windowsill and drywall.  This is due to cyclical wind pressures.",
                "Separation at window sill and wall due to cyclical wind pressures.  Shearing can be seen because of the diagonal stretching of the paint.  Paint has elastomeric properties and during shearing stress, one can see that the two side were shifted out of alignment."
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
                "Moisture present at leak location.",
                "Water stain is visible here."
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
    
    // Certification label photo categories (AAMA + NAMI)
    static let certificationLabelCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Certification Label",
            options: [
                "AAMA Certification Label",
                "No AAMA Certification Label",
                "AAMA Certification was unreadable",
                "NAMI Certification Label",
                "No NAMI Certification Label",
                "NAMI Certification was unreadable"
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: [] // Empty array indicates custom text input
        )
    ]

    // Interior Wide View categories (matches field app defaults for team customization editor)
    static let interiorWideViewCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Overview Photo",
            options: [
                "Interior view of the window.",
                "Wide view of interior.",
                "Wide view of the window from the interior.",
                "Wide view of the room containing the specimen.",
                "No testing performed. Air conditioning unit in window prevents testing."
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: []
        )
    ]

    static let interiorCloseupCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Separation/Cyclical Pressure Detailed",
            options: [
                "Cyclical wind pressure has caused separation between the window frame and the wall.",
                "Cyclical wind pressure has caused separation between the window frame and the wall.  This is common during high wind events.",
                "Some separation between windowsill and drywall.  This is due to cyclical wind pressures.",
                "There is a crack in the paint that spanned between the frame and the stucco.  This is due to movement from cyclical wind pressures.",
                "Separation at window sill and wall due to cyclical wind pressures.  Shearing can be seen because of the diagonal stretching of the paint.  Paint has elastomeric properties and during shearing stress, one can see that the two side were shifted out of alignment."
            ]
        ),
        PhotoNoteCategory(
            name: "Drywall Cracks",
            options: [
                "Drywall is separating from windowsill.",
                "Cracks at ceiling to wall connection.",
                "Separation at ceiling to wall joint near window."
            ]
        ),
        PhotoNoteCategory(
            name: "Frame to Wall",
            options: [
                "There is a crack between the frame and the drywall due to cyclical wind pressures.",
                "Crack between frame and drywall which is often caused by cyclical wind pressures.",
                "Interior Crack between frame and drywall.  This is typically due to cyclical wind pressures.",
                "Crack in drywall due to cyclical wind pressures.",
                "Recent crack at drywall due to cyclical wind pressures.",
                "This crack is an indication of cyclical pressure causing movement.",
                "Close-up of crack/separation in drywall.",
                "Cracking in drywall near frame; drywall cracks show signs of shear stress.",
                "Macro lens image shows the opening is fairly clean and free of debris.",
                "Interior frame separation from wall.",
                "Recent separation of the window frame and the drywall.",
                "Close-up of crack/separation between window frame and drywall."
            ]
        ),
        PhotoNoteCategory(
            name: "Window Frame Damage",
            options: [
                "Cracks at the window frame are often caused by cyclical pressures during storms.",
                "This crack in the window frame is an indication of cyclical pressure causing damage."
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: []
        )
    ]

    static let leakCloseupsCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Active Leak",
            options: [
                "Active water leak visible.",
                "Failed corner seals.",
                "Defective glazing gaskets.",
                "Sash/frame interface issues.",
                "Water entered at the top corner of the window frame.",
                "Water entered at the bottom corner of the window frame.",
                "Water enters through screw at frame.",
                "Water staining indicating leak.",
                "Moisture present at leak location.",
                "Water stain is visible here.",
                "Note - the paint is spanning gaps indicating recent movement.  This is typically caused by cyclical wind pressure."
            ]
        ),
        PhotoNoteCategory(
            name: "Leak Location",
            options: [
                "Water entered between window pane and frame.",
                "Leak at corner of window frame.",
                "Water entering at muntins/grills and window pane.",
                "Water entering at top of window frame.",
                "Water entered between window frame and head jamb.",
                "Water entering at mullion.",
                "Water entered between window pane and sash."
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
            options: []
        )
    ]

    static let exteriorWideViewCategories: [PhotoNoteCategory] = [
        PhotoNoteCategory(
            name: "Overview Photo",
            options: [
                "Wide view of exterior.",
                "Wide exterior view of the windows. Note: These wood frame windows are divided by a wood mullion. Due to the age and how these windows were installed, both windows would need to be replaced.",
                "Exterior view showing wide view of the window.",
                "Exterior view of the specimen.",
                "No testing performed. Air conditioning unit in window prevents testing."
            ]
        ),
        PhotoNoteCategory(
            name: "Custom/Other",
            options: []
        )
    ]

    static let exteriorPhotosCategories: [PhotoNoteCategory] = [
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
            name: "Commercial Window???",
            options: [
                "Water entered between window frame and wall.",
                "Water entered at bottom mullion."
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
            options: []
        )
    ]

    /// Hardcoded defaults for the team customization editor (ignores local overrides).
    static func builtInCategories(for photoType: PhotoType) -> [PhotoNoteCategory] {
        switch photoType {
        case .exterior:
            return exteriorCategories
        case .interior:
            return interiorCategories
        case .leak:
            return leakCategories
        case .aama:
            return certificationLabelCategories
        case .interiorWideView:
            return interiorWideViewCategories
        case .interiorCloseup:
            return interiorCloseupCategories
        case .leakCloseups:
            return leakCloseupsCategories
        case .exteriorWideView:
            return exteriorWideViewCategories
        case .exteriorPhotos:
            return exteriorPhotosCategories
        }
    }
    
    // Legacy support - returns exterior categories for backward compatibility
    static var categories: [PhotoNoteCategory] {
        return exteriorCategories
    }
    
    // Get categories for a specific photo type
    static func getCategories(for photoType: PhotoType) -> [PhotoNoteCategory] {
        switch photoType {
        case .exterior, .exteriorWideView, .exteriorPhotos:
            return exteriorCategories
        case .aama:
            return certificationLabelCategories
        case .interior, .interiorWideView, .interiorCloseup:
            return interiorCategories
        case .leak, .leakCloseups:
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

