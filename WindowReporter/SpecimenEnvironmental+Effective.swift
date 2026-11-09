import CoreData
import Foundation

/// Resolves per-specimen inspection date and display weather from job + optional specimen override.
enum SpecimenEnvironmental {

    struct DisplayWeather: Sendable {
        var temperature: Double
        var windSpeed: Double
    }

    static func effectiveInspectionDate(section: SpecimenSection, job: Job) -> Date? {
        if section.usesJobEnvironmentalDefaults {
            return job.inspectionDate
        }
        return section.specimenInspectionDate ?? job.inspectionDate
    }

    static func effectiveDisplayWeather(section: SpecimenSection, job: Job) -> DisplayWeather {
        if section.usesJobEnvironmentalDefaults {
            return displayWeatherFromJob(job)
        }
        let rawTemp = numberOrJob(section.specimenTemperature, job.temperature)
        let rawWind = numberOrJob(section.specimenWindSpeed, job.windSpeed)
        return DisplayWeather(
            temperature: rawTemp > 0 ? rawTemp : 73.0,
            windSpeed: rawWind > 0 ? rawWind : 5.0
        )
    }

    static func copyJobEnvironmentalSnapshot(from job: Job, to section: SpecimenSection) {
        section.specimenInspectionDate = job.inspectionDate
        section.specimenTemperature = NSNumber(value: job.temperature)
        section.specimenHumidity = NSNumber(value: job.humidity)
        section.specimenWindSpeed = NSNumber(value: job.windSpeed)
        section.specimenWeatherCondition = job.weatherCondition
        section.specimenWeatherFetchedAt = job.weatherFetchedAt
        section.specimenWeatherFetchedAddress = nil
    }

    static func clearSpecimenEnvironmentalOverride(section: SpecimenSection) {
        section.usesJobEnvironmentalDefaults = true
        section.specimenInspectionDate = nil
        section.specimenTemperature = nil
        section.specimenHumidity = nil
        section.specimenWindSpeed = nil
        section.specimenWeatherCondition = nil
        section.specimenWeatherFetchedAt = nil
        section.specimenWeatherFetchedAddress = nil
    }

    private static func numberOrJob(_ a: NSNumber?, _ fromJob: Double) -> Double {
        a.map { $0.doubleValue } ?? fromJob
    }

    private static func displayWeatherFromJob(_ job: Job) -> DisplayWeather {
        let t = job.temperature
        let w = job.windSpeed
        return DisplayWeather(
            temperature: t > 0 ? t : 73.0,
            windSpeed: w > 0 ? w : 5.0
        )
    }
}
