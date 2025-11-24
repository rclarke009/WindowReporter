//
//  AddressCleaningUtility.swift
//  WindowReporter
//
//  Created for macOS ReportWriter app
//

import Foundation

struct AddressCleaningUtility {
    /// Cleans an address by removing apartment/unit numbers and other suffixes that prevent proper geocoding
    /// - Parameter address: The original address string
    /// - Returns: The cleaned address with apartment/unit numbers removed
    static func cleanAddress(_ address: String) -> String {
        var cleaned = address.trimmingCharacters(in: .whitespaces)
        
        // Remove quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        // Patterns to remove (case-insensitive, with various separators)
        let patterns: [String] = [
            // Apartment patterns
            #",\s*Apt\.?\s*[A-Z0-9]+"#,
            #",\s*Apartment\s*[A-Z0-9]+"#,
            #"\s+Apt\.?\s*[A-Z0-9]+"#,
            #"\s+Apartment\s*[A-Z0-9]+"#,
            
            // Unit patterns
            #",\s*Unit\s*[A-Z0-9]+"#,
            #"\s+Unit\s*[A-Z0-9]+"#,
            #",\s*#\s*[A-Z0-9]+"#,
            #"\s+#\s*[A-Z0-9]+"#,
            
            // Suite patterns
            #",\s*Suite\s*[A-Z0-9]+"#,
            #",\s*Ste\.?\s*[A-Z0-9]+"#,
            #"\s+Suite\s*[A-Z0-9]+"#,
            #"\s+Ste\.?\s*[A-Z0-9]+"#,
            
            // Building patterns
            #",\s*Bldg\.?\s*[A-Z0-9]+"#,
            #",\s*Building\s*[A-Z0-9]+"#,
            #"\s+Bldg\.?\s*[A-Z0-9]+"#,
            #"\s+Building\s*[A-Z0-9]+"#,
        ]
        
        // Apply each pattern (case-insensitive)
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex?.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "") ?? cleaned
        }
        
        // Clean up any double spaces or trailing commas/spaces
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        
        return cleaned
    }
}

