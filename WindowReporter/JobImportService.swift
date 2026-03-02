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
        let equipmentCalibrationImage1File: String?
        let equipmentCalibrationImage2File: String?
        let weatherFetchedAt: Double?
        let internalNotes: String?
        let conclusionComment: String?
        let interiorFinishes: String?
        let exteriorFinishes: String?
        let jobStatus: String?
        let reportDeliveredAt: Double?
        let backedUpToArchiveAt: Double?
        let includeEngineeringLetter: Bool?
        let includeWeatherInReport: Bool?
        let customWeatherText: String?
        let customHurricaneImageFile: String?
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
        /// Specimen order (0-based). Optional for backward compatibility with packages exported before this field existed.
        let displayOrder: Int?
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
        let rotationDegrees: Double?
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
    @Published var importRefreshId = UUID()
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
    
    enum DuplicateResolution {
        case replace
        case skip
        case importAsNew
    }
    
    struct PendingDuplicateResolution {
        let package: FullJobPackage
        let directory: URL
        let existingJob: Job
        let isTempDirectory: Bool
    }
    
    @Published var pendingDuplicateResolution: PendingDuplicateResolution?
    
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
            pendingDuplicateResolution = nil
        }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.unableToAccessFile
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var tempDirectory: URL
            
            var isTempDirectory = false
            if url.pathExtension.lowercased() == "zip" {
                tempDirectory = documentsDirectory.appendingPathComponent("temp_import_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                isTempDirectory = true
                
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
            let fullJobPackageURL = tempDirectory.appendingPathComponent("full-job-package.json")
            let privateFullJobPackageURL = tempDirectory.appendingPathComponent("privatefull-job-package.json")
            let jobsJSONURL = tempDirectory.appendingPathComponent("jobs.json")
            
            print("🔍 Checking for JSON files:")
            print("   full-job-package.json at: \(fullJobPackageURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: fullJobPackageURL.path))")
            print("   privatefull-job-package.json at: \(privateFullJobPackageURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: privateFullJobPackageURL.path))")
            print("   jobs.json at: \(jobsJSONURL.path)")
            print("   exists: \(FileManager.default.fileExists(atPath: jobsJSONURL.path))")
            
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
                if let importedJob = try await importFullJobPackage(from: tempDirectory, isTempDirectory: isTempDirectory) {
                    if isTempDirectory {
                        try? FileManager.default.removeItem(at: tempDirectory)
                    }
                    await MainActor.run {
                        importProgress = 1.0
                        isImporting = false
                        self.importedJobs = [importedJob]
                        importRefreshId = UUID()
                        NotificationCenter.default.post(name: .newJobCreated, object: importedJob)
                    }
                } else {
                    await MainActor.run { isImporting = false }
                }
            } else if FileManager.default.fileExists(atPath: jobsJSONURL.path) {
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
                    importRefreshId = UUID()
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
        
        let archive: Archive
        do {
            archive = try Archive(url: sourceURL, accessMode: .read)
        } catch {
            print("❌ Failed to open ZIP archive: \(error.localizedDescription)")
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
            
            // Check current directory for JSON files
            let fullJobJSON = directory.appendingPathComponent("full-job-package.json")
            let privateFullJobJSON = directory.appendingPathComponent("privatefull-job-package.json")
            let jobsJSON = directory.appendingPathComponent("jobs.json")
            
            // Check for JSON files
            if FileManager.default.fileExists(atPath: fullJobJSON.path) ||
               FileManager.default.fileExists(atPath: privateFullJobJSON.path) ||
               FileManager.default.fileExists(atPath: jobsJSON.path) {
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
        let jobsJSONURL = directory.appendingPathComponent("jobs.json")
        
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
            job.testProcedure = "ASTM E1105"
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
    
    private func importFullJobPackage(from directory: URL, isTempDirectory: Bool = false) async throws -> Job? {
        // Check for JSON file with or without "private" prefix (like iPad version)
        // Check for JSON file (with or without iOS "private" prefix)
        var packageURL = directory.appendingPathComponent("full-job-package.json")
        if !FileManager.default.fileExists(atPath: packageURL.path) {
            let privateURL = directory.appendingPathComponent("privatefull-job-package.json")
            if FileManager.default.fileExists(atPath: privateURL.path) {
                packageURL = privateURL
                print("✅ Using full-job-package.json with iOS 'private' prefix")
            }
        }
        
        print("🔍 Looking for full-job-package.json at: \(packageURL.path)")
        
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            print("❌ full-job-package.json not found (checked both with and without 'private' prefix)")
            throw ImportError.missingFullJobPackage
        }
        
        print("✅ Found full-job-package.json, reading data...")
        
        let data = try Data(contentsOf: packageURL)
        print("📄 Read \(data.count) bytes from full-job-package.json")
        
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
        
        if let existingJob = existingJobs.first {
            await MainActor.run {
                pendingDuplicateResolution = PendingDuplicateResolution(
                    package: package,
                    directory: directory,
                    existingJob: existingJob,
                    isTempDirectory: isTempDirectory
                )
            }
            return nil
        }
        
        let job = Job(context: context)
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
        job.testProcedure = package.job.testProcedure ?? "ASTM E1105"
        job.waterPressure = package.job.waterPressure ?? 12.0
        job.inspectorName = package.job.inspectorName
        job.inspectionDate = package.job.inspectionDate.map { Date(timeIntervalSince1970: $0) }
        job.temperature = package.job.temperature ?? 0.0
        job.weatherCondition = package.job.weatherCondition
        job.humidity = package.job.humidity ?? 0.0
        job.windSpeed = package.job.windSpeed ?? 0.0
        job.createdAt = package.job.createdAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
        job.updatedAt = Date()
        job.weatherFetchedAt = package.job.weatherFetchedAt.map { Date(timeIntervalSince1970: $0) }
        job.internalNotes = package.job.internalNotes
        job.conclusionComment = package.job.conclusionComment
        job.interiorFinishes = package.job.interiorFinishes
        job.exteriorFinishes = package.job.exteriorFinishes
        job.jobStatus = package.job.jobStatus
        job.reportDeliveredAt = package.job.reportDeliveredAt.map { Date(timeIntervalSince1970: $0) }
        job.backedUpToArchiveAt = package.job.backedUpToArchiveAt.map { Date(timeIntervalSince1970: $0) }
        job.includeEngineeringLetter = package.job.includeEngineeringLetter ?? false
        job.includeWeatherInReport = package.job.includeWeatherInReport ?? true
        job.customWeatherText = package.job.customWeatherText
        
        try await applyFullJobPackage(package, from: directory, to: job)
        return job
    }
    
    private func applyFullJobPackage(_ package: FullJobPackage, from directory: URL, to job: Job) async throws {
        await MainActor.run { importProgress = 0.5 }
        
        if let overheadFile = package.job.overheadImageFile {
            print("📷 Importing overhead image: \(overheadFile)")
            try await importOverheadImage(from: directory, filePath: overheadFile, for: job)
        } else {
            print("⚠️ No overheadImageFile in package")
        }
        if let mapFile = package.job.wideMapImageFile {
            print("📷 Importing wide map image: \(mapFile)")
            try await importWideMapImage(from: directory, filePath: mapFile, for: job)
        } else {
            print("⚠️ No wideMapImageFile in package")
        }
        if let frontOfHomeFile = package.job.frontOfHomeImageFile {
            print("📷 Importing front of home image: \(frontOfHomeFile)")
            try await importFrontOfHomeImage(from: directory, filePath: frontOfHomeFile, for: job)
        } else {
            print("⚠️ No frontOfHomeImageFile in package")
        }
        if let gaugeFile = package.job.gaugeImageFile {
            print("📷 Importing gauge image: \(gaugeFile)")
            try await importGaugeImage(from: directory, filePath: gaugeFile, for: job)
        } else {
            print("⚠️ No gaugeImageFile in package")
        }
        if let calibration1File = package.job.equipmentCalibrationImage1File {
            print("📷 Importing equipment calibration image 1: \(calibration1File)")
            try await importEquipmentCalibrationImage(from: directory, filePath: calibration1File, for: job, slot: 1)
        }
        if let calibration2File = package.job.equipmentCalibrationImage2File {
            print("📷 Importing equipment calibration image 2: \(calibration2File)")
            try await importEquipmentCalibrationImage(from: directory, filePath: calibration2File, for: job, slot: 2)
        }
        if let hurricaneFile = package.job.customHurricaneImageFile {
            print("📷 Importing custom hurricane image: \(hurricaneFile)")
            try await importCustomHurricaneImage(from: directory, filePath: hurricaneFile, for: job)
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
            
            // Use displayOrder from file when present (preserves order from export); otherwise use array index for backward compatibility
            let orderFromFile = windowData.displayOrder ?? index
            
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
                window.displayOrder = Int32(orderFromFile)
                window.updatedAt = Date()
                // Replace path: remove existing photos so imported package photos don't duplicate
                if let existingPhotos = window.photos?.allObjects as? [Photo] {
                    for photo in existingPhotos {
                        context.delete(photo)
                    }
                }
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
                window.displayOrder = Int32(orderFromFile)
                window.job = job
            }
            
            // Import photos using file system storage (macOS-specific)
            print("MYDEBUG → JobImportService - Importing \(windowData.photos.count) photos for window \(window.windowNumber ?? "?")")
            for (photoIndex, photoData) in windowData.photos.enumerated() {
                print("MYDEBUG →   Importing photo \(photoIndex + 1)/\(windowData.photos.count): \(photoData.photoId)")
                try await importPhoto(from: directory, photoData: photoData, for: window)
            }
            
            // Refresh window after importing all photos
            context.refresh(window, mergeChanges: true)
            
            // Verify photos were imported
            let finalPhotoCount = window.photos?.count ?? 0
            print("MYDEBUG → JobImportService - Finished importing photos for window \(window.windowNumber ?? "?")")
            print("MYDEBUG →   Expected: \(windowData.photos.count) photos")
            print("MYDEBUG →   Actual: \(finalPhotoCount) photos")
            if let photosSet = window.photos {
                let photoArray = photosSet.allObjects as? [Photo] ?? []
                print("MYDEBUG →   Photo IDs:")
                for p in photoArray {
                    print("MYDEBUG →     - \(p.photoId ?? "nil") (\(p.photoType ?? "nil"))")
                }
            }
            
            let progress = 0.6 + (Double(index + 1) / Double(windowCount)) * 0.3
            await MainActor.run { importProgress = progress }
        }
        
        // Refresh all windows before final save
        print("MYDEBUG → JobImportService - Refreshing all windows before final save")
        for windowData in package.job.windows {
            let fetchRequest: NSFetchRequest<Window> = Window.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "windowId == %@ AND job == %@", windowData.windowId, job)
            fetchRequest.fetchLimit = 1
            if let window = try? context.fetch(fetchRequest).first {
                context.refresh(window, mergeChanges: true)
                let photoCount = window.photos?.count ?? 0
                print("MYDEBUG →   Window \(window.windowNumber ?? "?") has \(photoCount) photos")
            }
        }
        
        try context.save()
        
        // Final verification after save
        print("MYDEBUG → JobImportService - Final verification after save")
        for windowData in package.job.windows {
            let fetchRequest: NSFetchRequest<Window> = Window.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "windowId == %@ AND job == %@", windowData.windowId, job)
            fetchRequest.fetchLimit = 1
            if let window = try? context.fetch(fetchRequest).first {
                let photoCount = window.photos?.count ?? 0
                print("MYDEBUG →   Window \(window.windowNumber ?? "?") final photo count: \(photoCount)")
            }
        }
    }
    
    func resolveDuplicate(choice: DuplicateResolution) async {
        guard let pending = pendingDuplicateResolution else { return }
        
        switch choice {
        case .skip:
            if pending.isTempDirectory {
                try? FileManager.default.removeItem(at: pending.directory)
            }
            await MainActor.run {
                pendingDuplicateResolution = nil
                isImporting = false
            }
            
        case .replace:
            let job = pending.existingJob
            let p = pending.package.job
            if let v = p.clientName { job.clientName = v }
            if let v = p.addressLine1 { job.addressLine1 = v }
            if let v = p.cleanedAddressLine1 { job.cleanedAddressLine1 = v }
            if let v = p.city { job.city = v }
            if let v = p.state { job.state = v }
            if let v = p.zip { job.zip = v }
            if let v = p.notes { job.notes = v }
            if let v = p.phoneNumber { job.phoneNumber = v }
            if let v = p.areasOfConcern { job.areasOfConcern = v }
            if let v = p.status { job.status = v }
            if let v = p.testProcedure { job.testProcedure = v }
            if let v = p.waterPressure { job.waterPressure = v }
            if let v = p.inspectorName { job.inspectorName = v }
            if let v = p.inspectionDate { job.inspectionDate = Date(timeIntervalSince1970: v) }
            if let v = p.temperature { job.temperature = v }
            if let v = p.weatherCondition { job.weatherCondition = v }
            if let v = p.humidity { job.humidity = v }
            if let v = p.windSpeed { job.windSpeed = v }
            if let v = p.weatherFetchedAt { job.weatherFetchedAt = Date(timeIntervalSince1970: v) }
            if let v = p.internalNotes { job.internalNotes = v }
            if let v = p.conclusionComment { job.conclusionComment = v }
            if let v = p.interiorFinishes { job.interiorFinishes = v }
            if let v = p.exteriorFinishes { job.exteriorFinishes = v }
            if let v = p.jobStatus { job.jobStatus = v }
            if let v = p.reportDeliveredAt { job.reportDeliveredAt = Date(timeIntervalSince1970: v) }
            if let v = p.backedUpToArchiveAt { job.backedUpToArchiveAt = Date(timeIntervalSince1970: v) }
            if let v = p.includeEngineeringLetter { job.includeEngineeringLetter = v }
            if let v = p.includeWeatherInReport { job.includeWeatherInReport = v }
            if let v = p.customWeatherText { job.customWeatherText = v }
            job.updatedAt = Date()
            
            let didStartAccess = !pending.isTempDirectory && pending.directory.startAccessingSecurityScopedResource()
            defer { if didStartAccess { pending.directory.stopAccessingSecurityScopedResource() } }
            
            do {
                try await applyFullJobPackage(pending.package, from: pending.directory, to: job)
                if pending.isTempDirectory {
                    try? FileManager.default.removeItem(at: pending.directory)
                }
                await MainActor.run {
                    pendingDuplicateResolution = nil
                    importProgress = 1.0
                    isImporting = false
                    importedJobs = [job]
                    importRefreshId = UUID()
                    NotificationCenter.default.post(name: .newJobCreated, object: job)
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    pendingDuplicateResolution = nil
                    isImporting = false
                }
            }
            
        case .importAsNew:
            let newJobId = pending.package.job.jobId + "-" + UUID().uuidString
            let newJob = Job(context: context)
            let p = pending.package.job
            newJob.jobId = newJobId
            newJob.clientName = p.clientName
            newJob.addressLine1 = p.addressLine1
            newJob.cleanedAddressLine1 = p.cleanedAddressLine1 ?? AddressCleaningUtility.cleanAddress(p.addressLine1 ?? "")
            newJob.city = p.city
            newJob.state = p.state
            newJob.zip = p.zip
            newJob.notes = p.notes
            newJob.phoneNumber = p.phoneNumber
            newJob.areasOfConcern = p.areasOfConcern
            newJob.status = p.status ?? "Ready"
            newJob.testProcedure = p.testProcedure ?? "ASTM E1105"
            newJob.waterPressure = p.waterPressure ?? 12.0
            newJob.inspectorName = p.inspectorName
            newJob.inspectionDate = p.inspectionDate.map { Date(timeIntervalSince1970: $0) }
            newJob.temperature = p.temperature ?? 0.0
            newJob.weatherCondition = p.weatherCondition
            newJob.humidity = p.humidity ?? 0.0
            newJob.windSpeed = p.windSpeed ?? 0.0
            newJob.createdAt = p.createdAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
            newJob.updatedAt = Date()
            newJob.weatherFetchedAt = p.weatherFetchedAt.map { Date(timeIntervalSince1970: $0) }
            newJob.internalNotes = p.internalNotes
            newJob.conclusionComment = p.conclusionComment
            newJob.interiorFinishes = p.interiorFinishes
            newJob.exteriorFinishes = p.exteriorFinishes
            newJob.jobStatus = p.jobStatus
            newJob.reportDeliveredAt = p.reportDeliveredAt.map { Date(timeIntervalSince1970: $0) }
            newJob.backedUpToArchiveAt = p.backedUpToArchiveAt.map { Date(timeIntervalSince1970: $0) }
            newJob.includeEngineeringLetter = p.includeEngineeringLetter ?? false
            newJob.includeWeatherInReport = p.includeWeatherInReport ?? true
            newJob.customWeatherText = p.customWeatherText
            
            let didStartAccess = !pending.isTempDirectory && pending.directory.startAccessingSecurityScopedResource()
            defer { if didStartAccess { pending.directory.stopAccessingSecurityScopedResource() } }
            
            do {
                try await applyFullJobPackage(pending.package, from: pending.directory, to: newJob)
                if pending.isTempDirectory {
                    try? FileManager.default.removeItem(at: pending.directory)
                }
                await MainActor.run {
                    pendingDuplicateResolution = nil
                    importProgress = 1.0
                    isImporting = false
                    importedJobs = [newJob]
                    importRefreshId = UUID()
                    NotificationCenter.default.post(name: .newJobCreated, object: newJob)
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    pendingDuplicateResolution = nil
                    isImporting = false
                }
            }
        }
    }
    
    private func importOverheadImage(from directory: URL, filePath: String, for job: Job) async throws {
        // Strip leading slash if present (like ZIP extraction)
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        
        // Try multiple path combinations
        var sourceURL: URL?
        
        // Try 1: Direct path from directory
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
            print("📷 Found overhead image at direct path: \(directPath.path)")
        } else {
            // Try 2: If path includes overhead/, check overhead/ directory
            if imageFilePath.contains("overhead/") {
                let filename = (imageFilePath as NSString).lastPathComponent
                let overheadPath = directory.appendingPathComponent("overhead").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: overheadPath.path) {
                    sourceURL = overheadPath
                    print("📷 Found overhead image in overhead/: \(overheadPath.path)")
                }
            }
            
            // Try 3: Check for iOS "private" prefix on overhead/
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let privateOverheadPath = directory.appendingPathComponent("privateoverhead").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: privateOverheadPath.path) {
                    sourceURL = privateOverheadPath
                    print("📷 Found overhead image in privateoverhead/: \(privateOverheadPath.path)")
                }
            }
            
            // Try 4: Extract filename from path and look in overhead
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let overheadPath = directory.appendingPathComponent("overhead").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: overheadPath.path) {
                    sourceURL = overheadPath
                    print("📷 Found overhead image by filename in overhead: \(overheadPath.path)")
                }
            }
            
            // Try 5: If path already includes map/, use it as-is (for map images)
            if sourceURL == nil && imageFilePath.contains("map/") {
                let pathWithMap = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithMap.path) {
                    sourceURL = pathWithMap
                    print("📷 Found overhead image at path with map/: \(pathWithMap.path)")
                }
            }
            
            // Try 6: Check for iOS "private" prefix on map/
            if sourceURL == nil && imageFilePath.contains("map/") {
                let privatePath = imageFilePath.replacingOccurrences(of: "map/", with: "privatemap/")
                let pathWithPrivate = directory.appendingPathComponent(privatePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found overhead image at path with privatemap/: \(pathWithPrivate.path)")
                }
            }
            
            // Try 7: Add map/ prefix
            if sourceURL == nil {
                let mapPath = directory.appendingPathComponent("map").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: mapPath.path) {
                    sourceURL = mapPath
                    print("📷 Found overhead image at map path: \(mapPath.path)")
                }
            }
            
            // Try 8: Add privatemap/ prefix (iOS adds "private" prefix)
            if sourceURL == nil {
                let privateMapPath = directory.appendingPathComponent("privatemap").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: privateMapPath.path) {
                    sourceURL = privateMapPath
                    print("📷 Found overhead image at privatemap path: \(privateMapPath.path)")
                }
            }
        }
        
        guard let finalURL = sourceURL else {
            print("⚠️ Overhead image not found at any path for: \(filePath)")
            return
        }
        
        let overheadImagesDirectory = documentsDirectory.appendingPathComponent("overhead_images")
        try FileManager.default.createDirectory(at: overheadImagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_overhead.jpg"
        let destinationURL = overheadImagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        job.overheadImagePath = fileName
        print("✅ Successfully imported overhead image: \(fileName)")
    }
    
    private func importWideMapImage(from directory: URL, filePath: String, for job: Job) async throws {
        // Strip leading slash if present (like ZIP extraction)
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        
        // Try multiple path combinations
        var sourceURL: URL?
        
        // Try 1: Direct path from directory
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
            print("📷 Found wide map image at direct path: \(directPath.path)")
        } else {
            // Try 2: If path already includes map/, use it as-is
            if imageFilePath.contains("map/") {
                let pathWithMap = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithMap.path) {
                    sourceURL = pathWithMap
                    print("📷 Found wide map image at path with map/: \(pathWithMap.path)")
                }
            }
            
            // Try 3: Check for iOS "private" prefix on map/
            if sourceURL == nil && imageFilePath.contains("map/") {
                let privatePath = imageFilePath.replacingOccurrences(of: "map/", with: "privatemap/")
                let pathWithPrivate = directory.appendingPathComponent(privatePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found wide map image at path with privatemap/: \(pathWithPrivate.path)")
                }
            }
            
            // Try 4: Add map/ prefix
            if sourceURL == nil {
                let mapPath = directory.appendingPathComponent("map").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: mapPath.path) {
                    sourceURL = mapPath
                    print("📷 Found wide map image at map path: \(mapPath.path)")
                }
            }
            
            // Try 5: Add privatemap/ prefix (iOS adds "private" prefix)
            if sourceURL == nil {
                let privateMapPath = directory.appendingPathComponent("privatemap").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: privateMapPath.path) {
                    sourceURL = privateMapPath
                    print("📷 Found wide map image at privatemap path: \(privateMapPath.path)")
                }
            }
            
            // Try 6: Extract filename from path and look in map
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let filenamePath = directory.appendingPathComponent("map").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filenamePath.path) {
                    sourceURL = filenamePath
                    print("📷 Found wide map image by filename in map: \(filenamePath.path)")
                }
            }
            
            // Try 7: Extract filename from path and look in privatemap (iOS prefix)
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let filenamePath = directory.appendingPathComponent("privatemap").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filenamePath.path) {
                    sourceURL = filenamePath
                    print("📷 Found wide map image by filename in privatemap: \(filenamePath.path)")
                }
            }
        }
        
        guard let finalURL = sourceURL else {
            print("⚠️ Wide map image not found at any path for: \(filePath)")
            return
        }
        
        let mapImagesDirectory = documentsDirectory.appendingPathComponent("map_images")
        try FileManager.default.createDirectory(at: mapImagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_location_map.png"
        let destinationURL = mapImagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        job.wideMapImagePath = fileName
        print("✅ Successfully imported wide map image: \(fileName)")
    }
    
    private func importFrontOfHomeImage(from directory: URL, filePath: String, for job: Job) async throws {
        // Strip leading slash if present (like ZIP extraction)
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        
        // Try multiple path combinations
        var sourceURL: URL?
        
        // Try 1: Direct path from directory
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
            print("📷 Found front of home image at direct path: \(directPath.path)")
        } else {
            // Try 2: If path includes images/, check images/ directory directly
            if imageFilePath.contains("images/") {
                let pathWithImages = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithImages.path) {
                    sourceURL = pathWithImages
                    print("📷 Found front of home image at images/ path: \(pathWithImages.path)")
                }
            }
            
            // Try 3: Check for iOS "private" prefix on images/
            if sourceURL == nil && imageFilePath.contains("images/") {
                let privatePath = imageFilePath.replacingOccurrences(of: "images/", with: "privateimages/")
                let pathWithPrivate = directory.appendingPathComponent(privatePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found front of home image at privateimages/ path: \(pathWithPrivate.path)")
                }
            }
            
            // Try 4: Extract filename from path and look in images/ directory
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let imagesPath = directory.appendingPathComponent("images").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: imagesPath.path) {
                    sourceURL = imagesPath
                    print("📷 Found front of home image by filename in images/: \(imagesPath.path)")
                }
            }
            
            // Try 5: Extract filename from path and look in privateimages/ (iOS prefix)
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let privateImagesPath = directory.appendingPathComponent("privateimages").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: privateImagesPath.path) {
                    sourceURL = privateImagesPath
                    print("📷 Found front of home image by filename in privateimages/: \(privateImagesPath.path)")
                }
            }
            
            // Try 6: Check other possible directories (fallback)
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let possibleDirs = ["images", "privateimages", "front_of_home_images"]
                for dir in possibleDirs {
                    let testPath = directory.appendingPathComponent(dir).appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: testPath.path) {
                        sourceURL = testPath
                        print("📷 Found front of home image in \(dir): \(testPath.path)")
                        break
                    }
                }
            }
        }
        
        guard let finalURL = sourceURL else {
            print("⚠️ Front of home image not found at any path for: \(filePath)")
            return
        }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("front_of_home_images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_front_of_home.jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        job.frontOfHomeImagePath = fileName
        print("✅ Successfully imported front of home image: \(fileName)")
    }
    
    private func importGaugeImage(from directory: URL, filePath: String, for job: Job) async throws {
        // Strip leading slash if present (like ZIP extraction)
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        
        // Try multiple path combinations
        var sourceURL: URL?
        
        // Try 1: Direct path from directory
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
            print("📷 Found gauge image at direct path: \(directPath.path)")
        } else {
            // Try 2: If path includes images/, check images/ directory directly
            if imageFilePath.contains("images/") {
                let pathWithImages = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithImages.path) {
                    sourceURL = pathWithImages
                    print("📷 Found gauge image at images/ path: \(pathWithImages.path)")
                }
            }
            
            // Try 3: Check for iOS "private" prefix on images/
            if sourceURL == nil && imageFilePath.contains("images/") {
                let privatePath = imageFilePath.replacingOccurrences(of: "images/", with: "privateimages/")
                let pathWithPrivate = directory.appendingPathComponent(privatePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found gauge image at privateimages/ path: \(pathWithPrivate.path)")
                }
            }
            
            // Try 4: Extract filename from path and look in images/ directory
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let imagesPath = directory.appendingPathComponent("images").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: imagesPath.path) {
                    sourceURL = imagesPath
                    print("📷 Found gauge image by filename in images/: \(imagesPath.path)")
                }
            }
            
            // Try 5: Extract filename from path and look in privateimages/ (iOS prefix)
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let privateImagesPath = directory.appendingPathComponent("privateimages").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: privateImagesPath.path) {
                    sourceURL = privateImagesPath
                    print("📷 Found gauge image by filename in privateimages/: \(privateImagesPath.path)")
                }
            }
            
            // Try 6: Check other possible directories (fallback)
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let possibleDirs = ["images", "privateimages", "gauge_images"]
                for dir in possibleDirs {
                    let testPath = directory.appendingPathComponent(dir).appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: testPath.path) {
                        sourceURL = testPath
                        print("📷 Found gauge image in \(dir): \(testPath.path)")
                        break
                    }
                }
            }
        }
        
        guard let finalURL = sourceURL else {
            print("⚠️ Gauge image not found at any path for: \(filePath)")
            return
        }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("gauge_images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        let fileName = "\(job.jobId ?? UUID().uuidString)_gauge.jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        job.gaugeImagePath = fileName
        print("✅ Successfully imported gauge image: \(fileName)")
    }
    
    private func importEquipmentCalibrationImage(from directory: URL, filePath: String, for job: Job, slot: Int) async throws {
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        var sourceURL: URL?
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
        } else if imageFilePath.contains("images/") {
            let pathWithImages = directory.appendingPathComponent(imageFilePath)
            if FileManager.default.fileExists(atPath: pathWithImages.path) { sourceURL = pathWithImages }
        }
        if sourceURL == nil && imageFilePath.contains("images/") {
            let privatePath = imageFilePath.replacingOccurrences(of: "images/", with: "privateimages/")
            let pathWithPrivate = directory.appendingPathComponent(privatePath)
            if FileManager.default.fileExists(atPath: pathWithPrivate.path) { sourceURL = pathWithPrivate }
        }
        if sourceURL == nil {
            let filename = (imageFilePath as NSString).lastPathComponent
            for dir in ["images", "privateimages", "equipment_calibration"] {
                let testPath = directory.appendingPathComponent(dir).appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: testPath.path) {
                    sourceURL = testPath
                    break
                }
            }
        }
        guard let finalURL = sourceURL else {
            print("⚠️ Equipment calibration image \(slot) not found for: \(filePath)")
            return
        }
        let imagesDirectory = documentsDirectory.appendingPathComponent("equipment_calibration")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let fileName = "\(job.jobId ?? UUID().uuidString)_calibration_\(slot).jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        if slot == 1 {
            job.equipmentCalibrationImage1Path = fileName
        } else {
            job.equipmentCalibrationImage2Path = fileName
        }
        print("MYDEBUG → Successfully imported equipment calibration image \(slot): \(fileName)")
    }
    
    private func importCustomHurricaneImage(from directory: URL, filePath: String, for job: Job) async throws {
        var imageFilePath = filePath
        if imageFilePath.hasPrefix("/") {
            imageFilePath = String(imageFilePath.dropFirst())
        }
        var sourceURL: URL?
        let directPath = directory.appendingPathComponent(imageFilePath)
        if FileManager.default.fileExists(atPath: directPath.path) {
            sourceURL = directPath
        } else if imageFilePath.contains("images/") {
            let pathWithImages = directory.appendingPathComponent(imageFilePath)
            if FileManager.default.fileExists(atPath: pathWithImages.path) { sourceURL = pathWithImages }
        }
        if sourceURL == nil && imageFilePath.contains("images/") {
            let privatePath = imageFilePath.replacingOccurrences(of: "images/", with: "privateimages/")
            let pathWithPrivate = directory.appendingPathComponent(privatePath)
            if FileManager.default.fileExists(atPath: pathWithPrivate.path) { sourceURL = pathWithPrivate }
        }
        if sourceURL == nil {
            let filename = (imageFilePath as NSString).lastPathComponent
            for dir in ["images", "privateimages"] {
                let testPath = directory.appendingPathComponent(dir).appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: testPath.path) {
                    sourceURL = testPath
                    break
                }
            }
        }
        guard let finalURL = sourceURL else {
            print("⚠️ Custom hurricane image not found for: \(filePath)")
            return
        }
        let imagesDirectory = documentsDirectory.appendingPathComponent("custom_hurricane_images")
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let fileName = "\(job.jobId ?? UUID().uuidString)_custom_hurricane.jpg"
        let destinationURL = imagesDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: finalURL, to: destinationURL)
        job.customHurricaneImagePath = fileName
        print("✅ Successfully imported custom hurricane image: \(fileName)")
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
            // Try 2: If path already includes photos/, use it as-is
            if imageFilePath.contains("photos/") {
                let pathWithPhotos = directory.appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: pathWithPhotos.path) {
                    sourceURL = pathWithPhotos
                    print("📷 Found photo at path with photos/: \(pathWithPhotos.path)")
                }
            }
            
            // Try 3: Check for iOS "private" prefix on photos/
            if sourceURL == nil && imageFilePath.contains("photos/") {
                let privatePath = imageFilePath.replacingOccurrences(of: "photos/", with: "privatephotos/")
                let pathWithPrivate = directory.appendingPathComponent(privatePath)
                if FileManager.default.fileExists(atPath: pathWithPrivate.path) {
                    sourceURL = pathWithPrivate
                    print("📷 Found photo at path with privatephotos/: \(pathWithPrivate.path)")
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
            
            // Try 5: Add privatephotos/ prefix (iOS adds "private" prefix)
            if sourceURL == nil {
                let privatePhotosPath = directory.appendingPathComponent("privatephotos").appendingPathComponent(imageFilePath)
                if FileManager.default.fileExists(atPath: privatePhotosPath.path) {
                    sourceURL = privatePhotosPath
                    print("📷 Found photo at privatephotos path: \(privatePhotosPath.path)")
                }
            }
            
            // Try 6: Extract filename from path and look in photos
            if sourceURL == nil {
                let filename = (imageFilePath as NSString).lastPathComponent
                let filenamePath = directory.appendingPathComponent("photos").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filenamePath.path) {
                    sourceURL = filenamePath
                    print("📷 Found photo by filename in photos: \(filenamePath.path)")
                }
            }
            
            // Try 7: Extract filename from path and look in privatephotos (iOS prefix)
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
        print("MYDEBUG → rotationDegrees from package: \(photoData.rotationDegrees ?? -999)")
        
        // Import photo using file system storage
        let photo = try await photoImportService.importFromFile(
            url: sourceURL,
            window: window,
            photoType: photoType,
            note: photoData.notes
        )
        
        // Update photo metadata
        print("MYDEBUG → JobImportService - Updating photo metadata:")
        print("MYDEBUG →   Original photoId: \(photo.photoId ?? "nil")")
        print("MYDEBUG →   New photoId from package: \(photoData.photoId)")
        print("MYDEBUG →   Window: \(window.windowNumber ?? "nil")")
        
        photo.photoId = photoData.photoId
        photo.arrowXPosition = photoData.arrowXPosition ?? 0.0
        photo.arrowYPosition = photoData.arrowYPosition ?? 0.0
        photo.arrowDirection = photoData.arrowDirection
        photo.rotationDegrees = photoData.rotationDegrees ?? 0
        photo.includeInReport = photoData.includeInReport
        if let createdAt = photoData.createdAt {
            photo.createdAt = Date(timeIntervalSince1970: createdAt)
        }
        
        // Save context after updating metadata
        try context.save()
        
        // Refresh window to ensure relationship is visible
        context.refresh(window, mergeChanges: true)
        
        // Verify relationship
        let photoCount = window.photos?.count ?? 0
        print("MYDEBUG → JobImportService - Photo metadata updated and saved")
        print("MYDEBUG →   Final photoId: \(photo.photoId ?? "unknown")")
        print("MYDEBUG →   Window now has \(photoCount) photos")
        
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
            return "The ZIP file doesn't contain a jobs.json or full-job-package.json file"
        case .invalidJSONFormat:
            return "The data file has an invalid format"
        case .imageProcessingFailed:
            return "Failed to process images"
        case .photoImportFailed:
            return "Failed to import photos"
        case .missingFullJobPackage:
            return "The package doesn't contain a full-job-package.json file"
        case .invalidFullJobPackageFormat:
            return "The data file has an invalid format"
        }
    }
}

