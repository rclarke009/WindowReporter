//
//  JobImportService.swift
//  WindowReporter
//
//  macOS-compatible job import service
//

import Foundation
import CoreData
import AppKit
import ZIPFoundation
import Combine

// MARK: - Data Models (same as iPad version)

struct JobIntakePackage: Codable {
    let version: String
    let createdAt: Double
    let preparedBy: String
    let jobs: [JobData]
    
    struct JobData: Codable {
        let jobId: String
        let clientName: String
        let address: Address
        let notes: String?
        let phoneNumber: String?
        let areasOfConcern: String?
        let overhead: OverheadData?
        
        struct Address: Codable {
            let line1: String
            let city: String
            let state: String
            let zip: String?
        }
        
        struct OverheadData: Codable {
            let imageFile: String
            let source: SourceData?
            let scalePixelsPerFoot: Double?
            let zoomScale: Double?
            
            struct SourceData: Codable {
                let name: String
                let url: String
                let fetchedAt: Double
            }
        }
    }
}

struct FullJobPackage: Codable {
    let version: String
    let exportedAt: Double
    let exportedBy: String?
    let job: FullJobData
    
    struct FullJobData: Codable {
        let jobId: String
        let clientName: String?
        let addressLine1: String?
        let cleanedAddressLine1: String?
        let city: String?
        let state: String?
        let zip: String?
        let notes: String?
        let phoneNumber: String?
        let areasOfConcern: String?
        let status: String?
        let testProcedure: String?
        let waterPressure: Double?
        let inspectorName: String?
        let inspectionDate: Double?
        let temperature: Double?
        let weatherCondition: String?
        let humidity: Double?
        let windSpeed: Double?
        let createdAt: Double?
        let updatedAt: Double?
        let overheadImageFile: String?
        let wideMapImageFile: String?
        let frontOfHomeImageFile: String?
        let gaugeImageFile: String?
        let overheadImageSourceName: String?
        let overheadImageSourceUrl: String?
        let overheadImageFetchedAt: Double?
        let scalePixelsPerFoot: Double?
        let windows: [FullWindowData]
    }
    
    struct FullWindowData: Codable {
        let windowId: String
        let windowNumber: String
        let xPosition: Double
        let yPosition: Double
        let width: Double
        let height: Double
        let windowType: String?
        let material: String?
        let testResult: String?
        let leakPoints: Int16
        let isInaccessible: Bool
        let notes: String?
        let testStartTime: Double?
        let testStopTime: Double?
        let createdAt: Double?
        let updatedAt: Double?
        let photos: [FullPhotoData]
    }
    
    struct FullPhotoData: Codable {
        let photoId: String
        let photoType: String
        let imageFile: String
        let notes: String?
        let arrowXPosition: Double?
        let arrowYPosition: Double?
        let arrowDirection: String?
        let includeInReport: Bool
        let createdAt: Double?
    }
}

// MARK: - Import Service

class JobImportService: ObservableObject {
    @Published var isImporting = false
    @Published var importError: String?
    @Published var importProgress: Double = 0.0
    @Published var importedJobs: [Job] = []
    @Published var detectedPackageType: PackageType? = nil
    
    enum PackageType: String {
        case jobIntake = "Job Intake Package"
        case fullJob = "Full Job Package"
        
        var description: String {
            switch self {
            case .jobIntake:
                return "Starter file from Desktop Scraper (address and overhead image only)"
            case .fullJob:
                return "Complete job with field photos, windows, measurements, and test results"
            }
        }
        
        var icon: String {
            switch self {
            case .jobIntake:
                return "doc.badge.plus"
            case .fullJob:
                return "doc.badge.gearshape"
            }
        }
    }
    
    private let context: NSManagedObjectContext
    private let documentsDirectory: URL
    private let photoImportService: macOSPhotoImportService
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.photoImportService = macOSPhotoImportService(context: context)
    }
    
    func importJobPackage(from url: URL) async {
        await MainActor.run {
            isImporting = true
            importError = nil
            importProgress = 0.0
            detectedPackageType = nil
        }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.unableToAccessFile
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var tempDirectory: URL
            
            if url.pathExtension.lowercased() == "zip" {
                tempDirectory = documentsDirectory.appendingPathComponent("temp_import_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                defer {
                    try? FileManager.default.removeItem(at: tempDirectory)
                }
                
                await MainActor.run { importProgress = 0.1 }
                try await extractZIP(from: url, to: tempDirectory)
                
                // Use recursive search to find JSON directory (like iPad version)
                print("📁 Searching for JSON files in: \(tempDirectory.path)")
                if let jsonDirectory = findJSONDirectory(startingFrom: tempDirectory) {
                    tempDirectory = jsonDirectory
                    print("✅ Found JSON directory: \(tempDirectory.path)")
                } else {
                    print("⚠️ No JSON directory found, will check root directory")
                }
                
                await MainActor.run { importProgress = 0.3 }
            } else {
                tempDirectory = url
                await MainActor.run { importProgress = 0.2 }
            }
            
            // Check for JSON files (with and without "private" prefix, like iPad version)
            let fullJobPackageURL = tempDirectory.appendingPathComponent("full_job_package.json")
            let privateFullJobPackageURL = tempDirectory.appendingPathComponent("privatefull_job_package.json")
            let jobsJSONURL = tempDirectory.appendingPathComponent("jobs.json")
            let privateJobsJSONURL = tempDirectory.appendingPathComponent("privatejobs.json")
            
            print("🔍 Checking for JSON files:")
            print("   full_job_package.json at: \(fullJobPackageURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: fullJobPackageURL.path))")
            print("   privatefull_job_package.json at: \(privateFullJobPackageURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: privateFullJobPackageURL.path))")
            print("   jobs.json at: \(jobsJSONURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: jobsJSONURL.path))")
            print("   privatejobs.json at: \(privateJobsJSONURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: privateJobsJSONURL.path))")
            
            // List all files in tempDirectory for debugging
            if let contents = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) {
                print("📁 Files in tempDirectory:")
                for item in contents {
                    print("   - \(item.lastPathComponent)")
                }
            }
            
            if FileManager.default.fileExists(atPath: fullJobPackageURL.path) || FileManager.default.fileExists(atPath: privateFullJobPackageURL.path) {
                await MainActor.run {
                    detectedPackageType = .fullJob
                    importProgress = 0.3
                }
                let importedJob = try await importFullJobPackage(from: tempDirectory)
                await MainActor.run {
                    importProgress = 1.0
                    isImporting = false
                    self.importedJobs = [importedJob]
                    NotificationCenter.default.post(name: .newJobCreated, object: importedJob)
                }
            } else if FileManager.default.fileExists(atPath: jobsJSONURL.path) || FileManager.default.fileExists(atPath: privateJobsJSONURL.path) {
                await MainActor.run {
                    detectedPackageType = .jobIntake
                    importProgress = 0.3
                }
                let jobsData = try await parseJobsJSON(from: tempDirectory)
                await MainActor.run { importProgress = 0.5 }
                let importedJobs = try await processJobs(jobsData, from: tempDirectory)
                await MainActor.run {
                    importProgress = 1.0
                    isImporting = false
                    self.importedJobs = importedJobs
                    if let firstJob = importedJobs.first {
                        NotificationCenter.default.post(name: .newJobCreated, object: firstJob)
                    }
                }
            } else {
                throw ImportError.missingJobsJSON
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
                isImporting = false
                importProgress = 0.0
            }
        }
    }
    
    private func extractZIP(from sourceURL: URL, to destinationURL: URL) async throws {
        print("📦 Extracting ZIP from: \(sourceURL.path)")
        print("📦 To destination: \(destinationURL.path)")
        
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            print("❌ Failed to open ZIP archive")
            throw ImportError.unableToAccessFile
        }
        
        var extractedCount = 0
        for entry in archive {
            var entryPath = entry.path
            // Strip leading slash if present (ZIP files sometimes have absolute paths)
            if entryPath.hasPrefix("/") {
                entryPath = String(entryPath.dropFirst())
            }
            let destinationPath = destinationURL.appendingPathComponent(entryPath)
            let parentDir = destinationPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: destinationPath)
            extractedCount += 1
            if extractedCount <= 10 {
                print("   Extracted: \(entry.path) -> \(destinationPath.path)")
                // Verify file exists after extraction
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    print("      ✅ File verified at destination")
                } else {
                    print("      ⚠️ WARNING: File not found after extraction!")
                }
            }
        }
        print("✅ ZIP extraction completed: \(extractedCount) files extracted")
    }
    
    private func findJSONDirectory(startingFrom directory: URL, maxDepth: Int = 3, currentDepth: Int = 0) -> URL? {
        guard currentDepth < maxDepth else { return nil }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey])
            
            // Check current directory for JSON files (with and without "private" prefix)
            let fullJobJSON = directory.appendingPathComponent("full_job_package.json")
            let privateFullJobJSON = directory.appendingPathComponent("privatefull_job_package.json")
            let jobsJSON = directory.appendingPathComponent("jobs.json")
            let privateJobsJSON = directory.appendingPathComponent("privatejobs.json")
            
            // Check for JSON files
            if FileManager.default.fileExists(atPath: fullJobJSON.path) ||
               FileManager.default.fileExists(atPath: privateFullJobJSON.path) ||
               FileManager.default.fileExists(atPath: jobsJSON.path) ||
               FileManager.default.fileExists(atPath: privateJobsJSON.path) {
                print("✅ Found JSON directory at depth \(currentDepth): \(directory.path)")
                return directory
            }
            
            // Recursively check subdirectories
            for item in contents {
                let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    if let found = findJSONDirectory(startingFrom: item, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                        return found
                    }
                }
            }
        } catch {
            print("⚠️ Error searching directory: \(error)")
        }
        
        return nil
    }
    
    private func parseJobsJSON(from directory: URL) async throws -> JobIntakePackage {
        // Check for JSON file with or without "private" prefix (like iPad version)
        var jobsJSONURL = directory.appendingPathComponent("jobs.json")
        if !FileManager.default.fileExists(atPath: jobsJSONURL.path) {
            let privateJobsJSONURL = directory.appendingPathComponent("privatejobs.json")
            if FileManager.default.fileExists(atPath: privateJobsJSONURL.path) {
                jobsJSONURL = privateJobsJSONURL
                print("✅ Using jobs.json with 'private' prefix")
            }
        }
        
        print("🔍 Looking for jobs.json at: \(jobsJSONURL.path)")
        
        guard FileManager.default.fileExists(atPath: jobsJSONURL.path) else {
            print("❌ jobs.json not found at: \(jobsJSONURL.path)")
            throw ImportError.missingJobsJSON
        }
        
        print("✅ Found jobs.json, reading data...")
        
        let data = try Data(contentsOf: jobsJSONURL)
        print("📄 Read \(data.count) bytes from jobs.json")
        
        let decoder = JSONDecoder()
        
        do {
            let package = try decoder.decode(JobIntakePackage.self, from: data)
            print("✅ Successfully parsed JSON with \(package.jobs.count) jobs")
            return package
        } catch {
            print("❌ JSON parsing error: \(error)")
            if let decodingError = error as? DecodingError {
                print("❌ Decoding error details: \(decodingError)")
            }
            throw ImportError.invalidJSONFormat
        }
    }
    
    private func processJobs(_ package: JobIntakePackage, from directory: URL) async throws -> [Job] {
        var importedJobs: [Job] = []
        
        for (index, jobData) in package.jobs.enumerated() {
            let job = Job(context: context)
            job.jobId = jobData.jobId
            job.clientName = jobData.clientName
            job.addressLine1 = jobData.address.line1
            job.cleanedAddressLine1 = AddressCleaningUtility.cleanAddress(jobData.address.line1)
            job.city = jobData.address.city
            job.state = jobData.address.state
            job.zip = jobData.address.zip
            job.notes = jobData.notes
            job.phoneNumber = jobData.phoneNumber
            job.areasOfConcern = jobData.areasOfConcern
            job.status = "Ready"
            job.testProcedure = "ASTM E331"
            job.waterPressure = 12.0
            job.createdAt = Date()
            job.updatedAt = Date()
            
            importedJobs.append(job)
            
            if let overheadData = jobData.overhead {
                try await processOverheadImage(overheadData, for: job, from: directory)
            }
            
            try await processWideMapImage(for: job, from: directory)
            
            let progress = 0.5 + (Double(index + 1) / Double(package.jobs.count)) * 0.4
            await MainActor.run { importProgress = progress }
        }
        
        try context.save()
        return importedJobs
    }
    
    private func processOverheadImage(_ overheadData: JobIntakePackage.JobData.OverheadData, for job: Job, from directory: URL) async throws {
        let imagePath = overheadData.imageFile
        let sourceImageURL = directory.appendingPathComponent(imagePath)
        
        guard FileManager.default.fileExists(atPath: sourceImageURL.path) else {
            return
        }
        
        let overheadImagesDirectory = documentsDirectory.appendingPathComponent("overhead_images")
        try FileManager.default.createDirectory(at: overheadImagesDirectory, withIntermediateDirectories: true)
        
        let destinationImageURL = overheadImagesDirectory.appendingPathComponent("\(job.jobId ?? UUID().uuidString)_overhead.jpg")
        try FileManager.default.copyItem(at: sourceImageURL, to: destinationImageURL)
        
        job.overheadImagePath = destinationImageURL.lastPathComponent
        
        if let source = overheadData.source {
            job.overheadImageSourceName = source.name
            job.overheadImageSourceUrl = source.url
            job.overheadImageFetchedAt = Date(timeIntervalSince1970: source.fetchedAt)
        }
        
        if let scale = overheadData.scalePixelsPerFoot {
            job.scalePixelsPerFoot = scale
        } else if let zoomScale = overheadData.zoomScale {
            job.scalePixelsPerFoot = zoomScale * 10.0
        }
    }
    
    private func processWideMapImage(for job: Job, from directory: URL) async throws {
        let mapFileName = "\(job.jobId ?? UUID().uuidString)_location_map.png"
        let sourceMapURL = directory.appendingPathComponent("map").appendingPathComponent(mapFileName)
        
        guard FileManager.default.fileExists(atPath: sourceMapURL.path) else {
            return
        }
        
        let mapImagesDirectory = documentsDirectory.appendingPathComponent("map_images")
        try FileManager.default.createDirectory(at: mapImagesDirectory, withIntermediateDirectories: true)
        
        let destinationMapURL = mapImagesDirectory.appendingPathComponent(mapFileName)
        try FileManager.default.copyItem(at: sourceMapURL, to: destinationMapURL)
        job.wideMapImagePath = destinationMapURL.lastPathComponent
    }
    
    // MARK: - Full Job Package Import
    
    private func importFullJobPackage(from directory: URL) async throws -> Job {
        // Check for JSON file with or without "private" prefix (like iPad version)
        var packageURL = directory.appendingPathComponent("full_job_package.json")
        if !FileManager.default.fileExists(atPath: packageURL.path) {
            let privatePackageURL = directory.appendingPathComponent("privatefull_job_package.json")
            if FileManager.default.fileExists(atPath: privatePackageURL.path) {
                packageURL = privatePackageURL
                print("✅ Using full_job_package.json with 'private' prefix")
            }
        }
        
        print("🔍 Looking for full_job_package.json at: \(packageURL.path)")
        
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            print("❌ full_job_package.json not found")
            throw ImportError.missingFullJobPackage
        }
        
        print("✅ Found full_job_package.json, reading data...")
        
        let data = try Data(contentsOf: packageURL)
        print("📄 Read \(data.count) bytes from full_job_package.json")
        
        let decoder = JSONDecoder()
        let package: FullJobPackage
        do {
            package = try decoder.decode(FullJobPackage.self, from: data)
            print("✅ Successfully parsed full job package")
        } catch {
            print("❌ Failed to decode Full Job Package: \(error)")
            throw ImportError.invalidFullJobPackageFormat
        }
        
        await MainActor.run { importProgress = 0.4 }
        
        let fetchRequest: NSFetchRequest<Job> = Job.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "jobId == %@", package.job.jobId)
        fetchRequest.fetchLimit = 1
        
        let existingJobs = try context.fetch(fetchRequest)
        let job: Job
        
        if let existingJob = existingJobs.first {
            job = existingJob
            // Update job properties
            if let clientName = package.job.clientName { job.clientName = clientName }
            if let addressLine1 = package.job.addressLine1 { job.addressLine1 = addressLine1 }
            if let cleanedAddressLine1 = package.job.cleanedAddressLine1 { job.cleanedAddressLine1 = cleanedAddressLine1 }
            if let city = package.job.city { job.city = city }
            if let state = package.job.state { job.state = state }
            if let zip = package.job.zip { job.zip = zip }
            if let notes = package.job.notes { job.notes = notes }
            if let phoneNumber = package.job.phoneNumber { job.phoneNumber = phoneNumber }
            if let areasOfConcern = package.job.areasOfConcern { job.areasOfConcern = areasOfConcern }
            if let status = package.job.status { job.status = status }
            if let testProcedure = package.job.testProcedure { job.testProcedure = testProcedure }
            if let waterPressure = package.job.waterPressure { job.waterPressure = waterPressure }
            if let inspectorName = package.job.inspectorName { job.inspectorName = inspectorName }
            if let inspectionDate = package.job.inspectionDate { job.inspectionDate = Date(timeIntervalSince1970: inspectionDate) }
            if let temperature = package.job.temperature { job.temperature = temperature }
            if let weatherCondition = package.job.weatherCondition { job.weatherCondition = weatherCondition }
            if let humidity = package.job.humidity { job.humidity = humidity }
            if let windSpeed = package.job.windSpeed { job.windSpeed = windSpeed }
            job.updatedAt = Date()
        } else {
            job = Job(context: context)
            job.jobId = package.job.jobId
            job.clientName = package.job.clientName
            job.addressLine1 = package.job.addressLine1
            job.cleanedAddressLine1 = package.job.cleanedAddressLine1 ?? AddressCleaningUtility.cleanAddress(package.job.addressLine1 ?? "")
            job.city = package.job.city
            job.state = package.job.state
            job.zip = package.job.zip
            job.notes = package.job.notes
            job.phoneNumber = package.job.phoneNumber
            job.areasOfConcern = package.job.areasOfConcern
            job.status = package.job.status ?? "Ready"
            job.testProcedure = package.job.testProcedure ?? "ASTM E331"
            job.waterPressure = package.job.waterPressure ?? 12.0
            job.inspectorName = package.job.inspectorName
            job.inspectionDate = package.job.inspectionDate.map { Date(timeIntervalSince1970: $0) }
            job.temperature = package.job.temperature ?? 0.0
            job.weatherCondition = package.job.weatherCondition
            job.humidity = package.job.humidity ?? 0.0
            job.windSpeed = package.job.windSpeed ?? 0.0
            job.createdAt = package.job.createdAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
            job.updatedAt = Date()
        }
        
        await MainActor.run { importProgress = 0.5 }
        
        if let overheadFile = package.job.overheadImageFile {
            try await importOverheadImage(from: directory, filePath: overheadFile, for: job)
        }
        if let mapFile = package.job.wideMapImageFile {
            try await importWideMapImage(from: directory, filePath: mapFile, for: job)
        }
        if let frontOfHomeFile = package.job.frontOfHomeImageFile {
            try await importFrontOfHomeImage(from: directory, filePath: frontOfHomeFile, for: job)
        }
        if let gaugeFile = package.job.gaugeImageFile {
            try await importGaugeImage(from: directory, filePath: gaugeFile, for: job)
        }
        
        if let sourceName = package.job.overheadImageSourceName { job.overheadImageSourceName = sourceName }
        if let sourceUrl = package.job.overheadImageSourceUrl { job.overheadImageSourceUrl = sourceUrl }
        if let fetchedAt = package.job.overheadImageFetchedAt { job.overheadImageFetchedAt = Date(timeIntervalSince1970: fetchedAt) }
        if let scale = package.job.scalePixelsPerFoot { job.scalePixelsPerFoot = scale }
        
        await MainActor.run { importProgress = 0.6 }
        
        // Process windows
        let windowCount = package.job.windows.count
        for (index, windowData) in package.job.windows.enumerated() {
            let fetchRequest: NSFetchRequest<Window> = Window.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "windowId == %@ AND job == %@", windowData.windowId, job)
            fetchRequest.fetchLimit = 1
            
            let existingWindows = try context.fetch(fetchRequest)
            let window: Window
            
            if let existingWindow = existingWindows.first {
                window = existingWindow
                window.windowNumber = windowData.windowNumber
                window.xPosition = windowData.xPosition
                window.yPosition = windowData.yPosition
                window.width = windowData.width
                window.height = windowData.height
                window.windowType = windowData.windowType
                window.material = windowData.material
                window.testResult = windowData.testResult
                window.leakPoints = windowData.leakPoints
                window.isInaccessible = windowData.isInaccessible
                window.notes = windowData.notes
                window.testStartTime = windowData.testStartTime.map { Date(timeIntervalSince1970: $0) }
                window.testStopTime = windowData.testStopTime.map { Date(timeIntervalSince1970: $0) }
                window.updatedAt = Date()
            } else {
                window = Window(context: context)
                window.windowId = windowData.windowId
                window.windowNumber = windowData.windowNumber
                window.xPosition = windowData.xPosition
                window.yPosition = windowData.yPosition
                window.width = windowData.width
                window.height = windowData.height
                window.windowType = windowData.windowType
                window.material = windowData.material
                window.testResult = windowData.testResult
                window.leakPoints = windowData.leakPoints
                window.isInaccessible = windowData.isInaccessible
                window.notes = windowData.notes
                window.testStartTime = windowData.testStartTime.map { Date(timeIntervalSince1970: $0) }
                window.testStopTime = windowData.testStopTime.map { Date(timeIntervalSince1970: $0) }
                window.createdAt = windowData.createdAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
                window.updatedAt = Date()
                window.job = job
            }
            
            // Import photos using file system storage (macOS-specific)
            for photoData in windowData.photos {
                try await importPhoto(from: directory, photoData: photoData, for: window)
            }
            
            let progress = 0.6 + (Double(index + 1) / Double(windowCount)) * 0.3
            await MainActor.run { importProgress = progress }
        }
        
        try context.save()
        return job
    }
    
    private func importOverheadImage(from directory: URL, filePath: String, for job: Job) async throws {
        let sourceURL = directory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        
        let overheadImagesDirectory = documentsDirectory.appendingPathComponent("overhead_images")
        try FileManager.default.createDirectory(at: overheadImagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_overhead.jpg"
        let destinationURL = overheadImagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        job.overheadImagePath = fileName
    }
    
    private func importWideMapImage(from directory: URL, filePath: String, for job: Job) async throws {
        let sourceURL = directory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        
        let mapImagesDirectory = documentsDirectory.appendingPathComponent("map_images")
        try FileManager.default.createDirectory(at: mapImagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_location_map.png"
        let destinationURL = mapImagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        job.wideMapImagePath = fileName
    }
    
    private func importFrontOfHomeImage(from directory: URL, filePath: String, for job: Job) async throws {
        let sourceURL = directory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("front_of_home_images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_front_of_home.jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        job.frontOfHomeImagePath = fileName
    }
    
    private func importGaugeImage(from directory: URL, filePath: String, for job: Job) async throws {
        let sourceURL = directory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("gauge_images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_gauge.jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        job.gaugeImagePath = fileName
    }
    
    // MARK: - Photo Import (macOS: uses file system instead of Photos library)
    
    private func importPhoto(from directory: URL, photoData: FullJobPackage.FullPhotoData, for window: Window) async throws {
        // Strip leading slash if present (like ZIP extraction)
        var imageFilePath = photoData.imageFile
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        
        // Try multiple path combinations
        var sourceURL: URL?
        
        // Try 1: Direct path from directory
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
            print("📷 Found photo at direct path: \(directPath.path)")
        } else {
            // Try 2: If path already includes privatephotos/, use it as-is
            if imageFilePath.contains("privatephotos/") {
                let pathWithPrivate = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found photo at path with privatephotos/: \(pathWithPrivate.path)")
                }
            }
            
            // Try 3: Add privatephotos/ prefix
            if sourceURL == nil {
                let privatePath = directory.appendingPathComponent("privatephotos").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: privatePath.path) {
                    sourceURL = privatePath
                    print("📷 Found photo at privatephotos path: \(privatePath.path)")
                }
            }
            
            // Try 4: Add photos/ prefix
            if sourceURL == nil {
                let photosPath = directory.appendingPathComponent("photos").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: photosPath.path) {
                    sourceURL = photosPath
                    print("📷 Found photo at photos path: \(photosPath.path)")
                }
            }
            
            // Try 5: Extract filename from path and look in privatephotos
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let filenamePath = directory.appendingPathComponent("privatephotos").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filenamePath.path) {
                    sourceURL = filenamePath
                    print("📷 Found photo by filename in privatephotos: \(filenamePath.path)")
                }
            }
        }
        
        guard let finalURL = sourceURL else {
            print("⚠️ Photo image not found at any path for: \(photoData.imageFile)")
            return
        }
        
        try await importPhotoFromURL(finalURL, photoData: photoData, for: window)
    }
    
    private func importPhotoFromURL(_ sourceURL: URL, photoData: FullJobPackage.FullPhotoData, for window: Window) async throws {
        // Use macOSPhotoImportService to import to file system
        guard let photoType = PhotoType(rawValue: photoData.photoType) else {
            print("⚠️ Invalid photo type: \(photoData.photoType)")
            return
        }
        
        print("📷 Importing photo: \(sourceURL.lastPathComponent) for window \(window.windowNumber ?? "?")")
        
        // Import photo using file system storage
        let photo = try await photoImportService.importFromFile(
            url: sourceURL,
            window: window,
            photoType: photoType,
            note: photoData.notes
        )
        
        // Update photo metadata
        photo.photoId = photoData.photoId
        photo.arrowXPosition = photoData.arrowXPosition ?? 0.0
        photo.arrowYPosition = photoData.arrowYPosition ?? 0.0
        photo.arrowDirection = photoData.arrowDirection
        photo.includeInReport = photoData.includeInReport
        if let createdAt = photoData.createdAt {
            photo.createdAt = Date(timeIntervalSince1970: createdAt)
        }
        
        print("✅ Successfully imported photo: \(photo.photoId ?? "unknown")")
    }
}

enum ImportError: LocalizedError {
    case unableToAccessFile
    case missingJobsJSON
    case invalidJSONFormat
    case imageProcessingFailed
    case photoImportFailed
    case missingFullJobPackage
    case invalidFullJobPackageFormat
    
    var errorDescription: String? {
        switch self {
        case .unableToAccessFile:
            return "Unable to access the selected file"
        case .missingJobsJSON:
            return "The ZIP file doesn't contain a jobs.json or full_job_package.json file"
        case .invalidJSONFormat:
            return "The JSON file has an invalid format"
        case .imageProcessingFailed:
            return "Failed to process images"
        case .photoImportFailed:
            return "Failed to import photos"
        case .missingFullJobPackage:
            return "The package doesn't contain a full_job_package.json file"
        case .invalidFullJobPackageFormat:
            return "The full_job_package.json file has an invalid format"
        }
    }
}

