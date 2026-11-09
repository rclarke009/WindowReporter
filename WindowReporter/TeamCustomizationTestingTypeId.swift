//
//  TeamCustomizationTestingTypeId.swift
//  WindowReporter
//
//  Same ids as field app (WindowTest/TestingTypes.swift) for procedure/type editors.
//

import Foundation

enum TestingTypeId: String, CaseIterable, Identifiable {
    case windows = "windows"
    case roof = "roof"
    case attic = "attic"
    case floors = "floors"
    case walls = "walls"
    case structural = "structural"
    case electrical = "electrical"
    case moldMoisture = "moldMoisture"
    case siding = "siding"
    case doors = "doors"

    var id: String { rawValue }

    var defaultDisplayName: String {
        switch self {
        case .windows: return "Windows"
        case .roof: return "Roof"
        case .attic: return "Attic"
        case .floors: return "Floors"
        case .walls: return "Walls"
        case .structural: return "Structural"
        case .electrical: return "Electrical"
        case .moldMoisture: return "Mold/Moisture"
        case .siding: return "Siding"
        case .doors: return "Doors"
        }
    }
}
