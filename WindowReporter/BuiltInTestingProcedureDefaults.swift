//
//  BuiltInTestingProcedureDefaults.swift
//  WindowReporter
//
//  Built-in testing procedure step lists for each `TestingTypeId` when the org
//  has no Supabase row. Keep labels aligned with the field app (PhotoType names,
//  report language) where applicable.
//

import Foundation

enum BuiltInTestingProcedureDefaults {
    private static let genericFallback = CachedProcedureConfig(steps: [
        step("overview_photos", "Overview Photos", "photoRequirement"),
        step("damage_photos", "Damage Documentation Photos", "photoRequirement"),
        step("notes", "Notes", "text"),
    ])

    static func defaultConfig(for typeId: String) -> CachedProcedureConfig {
        switch typeId {
        case "windows": return windows
        case "doors": return doors
        case "roof": return roof
        case "floors": return floors
        case "walls": return walls
        case "structural": return structural
        case "electrical": return electrical
        case "moldMoisture": return moldMoisture
        case "siding": return siding
        case "attic": return attic
        default: return genericFallback
        }
    }

    // MARK: - Per-type configs

    private static var windows: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("equipment_calibration", "Equipment / calibration photos", "photoRequirement"),
            step("leak_closeups", "Leak Close-ups", "photoRequirement"),
            step("exterior_wide_view", "Exterior Wide View", "photoRequirement"),
            step("exterior_photos", "Exterior Photos", "photoRequirement"),
            step("interior_wide_view", "Interior Wide View", "photoRequirement"),
            step("interior_closeup_damage", "Interior Close-up & Damage", "photoRequirement"),
            step("water_test", "ASTM E1105 water-spray test performed", "toggle"),
            step("timer_notes", "Start/stop times or timer notes (15 min typical for spray test)", "text"),
            step("visual_inspection", "Visually inspect seals, caulking, flashing, sill, and frame (notes)", "text"),
            step("water_intrusion", "Record any water intrusion (notes)", "text"),
            step("certification_label", "Certification Label", "photoRequirement"),
        ])
    }

    private static var doors: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("door_type", "Door type (frame / material)", "picker", options: [
                "Aluminum", "Wood", "Fiberglass", "Steel", "Other",
            ]),
            step("threshold_style", "Threshold / sill style", "picker", options: [
                "Saddle", "Outswing low profile", "Inswing with threshold", "No threshold (flush)", "Other",
            ]),
            step("leak_closeups", "Leak Close-ups", "photoRequirement"),
            step("exterior_wide_view", "Exterior Wide View", "photoRequirement"),
            step("exterior_photos", "Exterior Photos", "photoRequirement"),
            step("interior_wide_view", "Interior Wide View", "photoRequirement"),
            step("interior_closeup_damage", "Interior Close-up & Damage", "photoRequirement"),
            step("water_test", "ASTM E1105 water-spray test performed (frame and sill)", "toggle"),
            step("timer_notes", "Start/stop times or timer notes (15 min typical)", "text"),
            step("certification_or_weatherstrip", "Certification label or weatherstripping close-up", "photoRequirement"),
            step("procedure_notes", "Check weatherstripping, thresholds, sweeps, hinges (notes)", "text"),
        ])
    }

    private static var roof: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("roofing_material", "Roofing material", "picker", options: [
                "Asphalt Shingle", "Metal", "Tile", "Flat Membrane", "Wood Shake", "Other",
            ]),
            step("slope_or_area", "Slope or approximate area (measurement / notes)", "measurement"),
            step("exterior_wide", "Exterior wide view (drone, ladder, or elevated)", "photoRequirement"),
            step("exterior_closeups", "Exterior close-ups (shingles, flashing, penetrations, damage)", "photoRequirement"),
            step("interior_wide", "Interior wide (attic or ceiling below)", "photoRequirement"),
            step("interior_closeup_damage", "Interior close-up & damage, stains, leaks", "photoRequirement"),
            step("section_spray_test", "Targeted spray test of section (if performed)", "toggle"),
            step("visual_exterior", "Visual: shingles/membrane, flashing, vents, chimneys, gutters (notes)", "text"),
            step("visual_interior", "Interior: stains, mold, active leaks (notes)", "text"),
        ])
    }

    private static var floors: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("floor_type", "Floor / substrate type", "picker", options: [
                "Concrete Slab", "Wood Subfloor", "Tile", "Carpet", "Other",
            ]),
            step("size_or_area", "Width & height or area (sq ft) / level notes", "measurement"),
            step("wide_view", "Wide view", "photoRequirement"),
            step("closeup_damage", "Close-up & damage (soft spots, buckling, discoloration)", "photoRequirement"),
            step("moisture_readings", "Moisture meter or test patch photos", "photoRequirement"),
            step("vapor_test", "ASTM F2170 / F1869 or similar moisture / vapor check (if applicable)", "toggle"),
            step("long_test_notes", "Long-cycle test start/end notes (24–72 hr methods)", "text"),
            step("procedure_notes", "Visual + moisture scan; record soft spots, cupping, prior water damage (notes)", "text"),
        ])
    }

    private static var walls: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("wall_type", "Wall type", "picker", options: [
                "Drywall", "Plaster", "Stucco", "Brick", "Siding on stud", "Other",
            ]),
            step("section_size", "Height & width of tested section", "measurement"),
            step("wide_view_interior", "Wide view (interior)", "photoRequirement"),
            step("wide_view_exterior", "Wide view (exterior, if applicable)", "photoRequirement"),
            step("closeup_damage", "Close-up & damage, cracks, stains", "photoRequirement"),
            step("leak_closeups", "Leak close-ups (if testing)", "photoRequirement"),
            step("moisture_scan", "Moisture meter scan performed", "toggle"),
            step("e2128_test", "ASTM E2128-style water intrusion test (if performed)", "toggle"),
            step("crack_width", "Crack width (if measured)", "measurement"),
            step("procedure_notes", "Visual, efflorescence, paint failure; record intrusion (notes)", "text"),
        ])
    }

    private static var structural: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("element_type", "Structural element", "picker", options: [
                "Foundation", "Beams", "Joists", "Columns", "Trusses", "Load-bearing wall", "Other",
            ]),
            step("dimensions", "Relevant dimensions or deflection reading notes", "measurement"),
            step("wide_view", "Wide view", "photoRequirement"),
            step("closeup_damage", "Close-up & damage (cracks, sag, rot, rust)", "photoRequirement"),
            step("engineer_recommended", "Engineer review recommended", "toggle"),
            step("procedure_notes", "Visual: cracks, settlement, rot, connections, fasteners (notes)", "text"),
        ])
    }

    private static var electrical: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("panel_type", "Panel / system", "picker", options: [
                "Main Service Panel", "Subpanel", "Outlets", "Switches", "Wiring", "Other",
            ]),
            step("voltage", "System voltage (if noted)", "picker", options: [
                "120/240V Residential", "208V", "480V", "Other", "N/A",
            ]),
            step("wide_view", "Wide view (panel and affected rooms)", "photoRequirement"),
            step("closeup_wiring", "Close-up: panel label, breakers, wiring, outlets, damage", "photoRequirement"),
            step("gfci_test", "GFCI / AFCI / polarity checks performed", "toggle"),
            step("panel_issues", "Panel issues noted (overloads, double-tap, etc.)", "text"),
        ])
    }

    private static var moldMoisture: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("surface_type", "Surface type", "picker", options: [
                "Drywall", "Wood", "Concrete", "Tile", "Other",
            ]),
            step("moisture_pct", "Moisture meter % readings (multiple spots — notes)", "text"),
            step("wide_view", "Wide view", "photoRequirement"),
            step("closeup_mold", "Close-up & damage / visible mold", "photoRequirement"),
            step("meter_photo", "Moisture meter in photo (if used)", "photoRequirement"),
            step("sampling", "Air / surface sampling performed", "toggle"),
            step("procedure_notes", "Odor, stains, pin/pinless meter, IR; record findings (notes)", "text"),
        ])
    }

    private static var siding: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("siding_type", "Siding type", "picker", options: [
                "Vinyl", "Fiber Cement", "Wood", "Stucco", "Brick", "Other",
            ]),
            step("section_size", "Height of section or linear feet", "measurement"),
            step("exterior_wide", "Exterior wide view", "photoRequirement"),
            step("exterior_closeups", "Exterior close-ups (damage, gaps, rot)", "photoRequirement"),
            step("leak_closeups", "Leak close-ups (if testing)", "photoRequirement"),
            step("e2128_spray", "ASTM E2128-style spray on wall (if performed)", "toggle"),
            step("flashing", "Flashing at windows, doors, roof (notes)", "text"),
        ])
    }

    private static var attic: CachedProcedureConfig {
        CachedProcedureConfig(steps: [
            step("attic_type", "Attic type", "picker", options: [
                "Unfinished", "Finished room", "Partially finished", "Cathedral / vaulted", "Crawl with scuttle", "Other",
            ]),
            step("insulation_type", "Insulation type", "picker", options: [
                "Blown-in fiberglass", "Cellulose", "Batt", "Spray foam", "None / unknown", "Other",
            ]),
            step("insulation_depth", "Avg insulation depth (in) or area notes", "measurement"),
            step("access_safety", "Access / safety limitations (headroom, opening size, hazards)", "text"),
            step("access_wide", "Attic access / wide view from entry", "photoRequirement"),
            step("insulation_closeups", "Insulation coverage & depth close-ups", "photoRequirement"),
            step("sheathing_wide", "Roof sheathing / rafters / trusses wide view", "photoRequirement"),
            step("leak_moisture", "Leak, stain, moisture close-ups", "photoRequirement"),
            step("ventilation", "Ventilation (soffit, ridge, gable, fans)", "photoRequirement"),
            step("ducts_mep", "Exhaust ducts / plumbing / electrical in attic", "photoRequirement"),
            step("pests", "Pest evidence (droppings, nests, damaged insulation)", "photoRequirement"),
            step("observation_timer", "Observation period or fan test (optional timer notes)", "text"),
            step("procedure_checklist", "Walk joists, inspect leaks, vent paths, terminations, structure (summary notes)", "text"),
        ])
    }

    // MARK: - Helpers

    private static func step(
        _ id: String,
        _ label: String,
        _ fieldType: String,
        options: [String]? = nil
    ) -> CachedProcedureStep {
        CachedProcedureStep(
            id: id, label: label, fieldType: fieldType, options: options,
            enabled: true, isBuiltIn: true
        )
    }
}
