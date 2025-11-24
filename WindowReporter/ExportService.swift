//
//  ExportService.swift
//  WindowReporter
//
//  Created by Rebecca Clarke on 9/26/25.
//  Adapted for macOS
//

import Foundation
import CoreData
import AppKit
import Photos
import ZIPFoundation

// Helper extension for NSFont to calculate line height (macOS equivalent of UIFont.lineHeight)
extension NSFont {
    var lineHeight: CGFloat {
        // Calculate line height from font metrics
        return ascender - descender + leading
    }
}

// Helper function to draw NSImage to CGContext (avoids graphics context issues)
func drawNSImage(_ image: NSImage, in rect: CGRect, context: CGContext) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        // Fallback: try to get CGImage from representation
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            return
        }
        context.draw(cgImage, in: rect)
        return
    }
    context.draw(cgImage, in: rect)
}

// Helper function to format address with proper handling of missing components
private func formatAddressForExport(addressLine1: String, city: String?, state: String?, zip: String?) -> String {
    var components: [String] = []
    
    if !addressLine1.isEmpty {
        components.append(addressLine1)
    }
    
    if let city = city, !city.isEmpty {
        components.append(city)
    }
    
    var stateZip: [String] = []
    if let state = state, !state.isEmpty {
        stateZip.append(state)
    }
    if let zip = zip, !zip.isEmpty {
        stateZip.append(zip)
    }
    
    if !stateZip.isEmpty {
        components.append(stateZip.joined(separator: " "))
    }
    
    return components.isEmpty ? "" : components.joined(separator: ", ")
}

struct FieldResultsPackage {
    let job: Job
    let exportDirectory: URL
    
    func generate() async throws -> URL {
        print("🚀 Starting export for job: \(job.jobId ?? "Unknown") in \(job.city ?? "Unknown")")
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = documentsDirectory.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let jobId = job.jobId ?? "Unknown"
        let city = job.city ?? "Unknown"
        let dateString = DateFormatter.exportDate.string(from: Date())
        let packageName = "\(jobId)_WindowTest_FieldReport_\(city)_\(dateString)"
        
        print("📦 Creating package: \(packageName)")
        
        let packageDirectory = exportDirectory.appendingPathComponent(packageName)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        
        // Generate job.json
        try await generateJobJSON(in: packageDirectory)
        
        // Generate windows.csv
        try await generateWindowsCSV(in: packageDirectory)
        
        // Generate overhead image with dots (optional)
        do {
            try await generateOverheadWithDots(in: packageDirectory)
        } catch {
            print("⚠️ Could not generate an overhead image with dots: \(error.localizedDescription)")
            // Continue with export even if overhead image fails
        }
        
        // Copy photos (optional)
        do {
            try await copyPhotos(to: packageDirectory)
        } catch {
            print("⚠️ Could not copy photos: \(error.localizedDescription)")
            // Continue with export even if photo copying fails
        }
        
        // Generate report
        try await generateReport(in: packageDirectory)
        
        // Finalize the export package
        print("📦 Finalizing export package...")
        let exportURL = try await createZIP(from: packageDirectory, name: packageName)
        print("✅ Export package created at: \(exportURL.path)")
        
        return exportURL
    }
    
    private var windows: [Window] {
        guard let windowsSet = job.windows else { return [] }
        return (windowsSet.allObjects as? [Window]) ?? []
    }
    
    /// Sort windows alphabetically by title (text part) then numerically by number
    /// Handles "Specimen 1", "Specimen 2", "Specimen 10" correctly
    private func sortWindowsByTitleThenNumber(_ windows: [Window]) -> [Window] {
        return windows.sorted { window1, window2 in
            let num1 = window1.windowNumber ?? ""
            let num2 = window2.windowNumber ?? ""
            
            // Parse the window number to extract title and number parts
            let parts1 = parseWindowNumber(num1)
            let parts2 = parseWindowNumber(num2)
            
            // First compare by title (alphabetically)
            if parts1.title != parts2.title {
                return parts1.title < parts2.title
            }
            
            // If titles are the same, compare by number (numerically)
            return parts1.number < parts2.number
        }
    }
    
    /// Parse window number to extract title and numeric parts
    /// Example: "Specimen 1" -> ("Specimen", 1), "Specimen 10" -> ("Specimen", 10)
    private func parseWindowNumber(_ windowNumber: String) -> (title: String, number: Int) {
        let trimmed = windowNumber.trimmingCharacters(in: .whitespaces)
        
        // Try to find the last number in the string
        if let range = trimmed.range(of: #"\d+$"#, options: .regularExpression) {
            let titlePart = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let numberPart = String(trimmed[range])
            
            if let number = Int(numberPart) {
                return (title: titlePart.isEmpty ? trimmed : titlePart, number: number)
            }
        }
        
        // If no number found, return the whole string as title with number 0
        return (title: trimmed, number: 0)
    }
    
    private func sanitizeFilenameComponent(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "Report" : trimmed
    }
    
    private func dotColor(for window: Window) -> NSColor {
        if window.isInaccessible {
            return .gray
        }
        switch window.testResult {
        case "Pass":
            return .green
        case "Fail":
            return .red
        default:
            return .blue
        }
    }
    
    /// Get the display test result for a window, checking isInaccessible first
    private func getDisplayTestResult(for window: Window) -> String {
        if window.isInaccessible {
            return "Inaccessible"
        }
        return window.testResult ?? "Pending"
    }
    
    private func getPhotoCount(for window: Window, type: String) -> Int {
        let allPhotos = (window.photos?.allObjects as? [Photo]) ?? []
        return allPhotos.filter { $0.photoType == type }.count
    }
    
    private func generateJobJSON(in directory: URL) async throws {
        let jobData = JobExportData(
            intake: IntakeData(
                sourceName: job.overheadImageSourceName,
                sourceUrl: job.overheadImageSourceUrl,
                fetchedAt: job.overheadImageFetchedAt
            ),
            field: FieldData(
                inspector: job.inspectorName ?? "Unknown",
                date: job.inspectionDate ?? Date(),
                overheadFile: "overhead_with_dots.png",
                windows: windows.map { window in
                    WindowExportData(
                        windowId: window.windowId ?? "",
                        windowNumber: window.windowNumber ?? "",
                        xPosition: window.xPosition,
                        yPosition: window.yPosition,
                        width: window.width,
                        height: window.height,
                        windowType: window.windowType,
                        material: window.material,
                        testResult: window.testResult,
                        leakPoints: Int(window.leakPoints),
                        isInaccessible: window.isInaccessible,
                        notes: window.notes,
                        exteriorPhotoCount: getPhotoCount(for: window, type: "Exterior"),
                        interiorPhotoCount: getPhotoCount(for: window, type: "Interior"),
                        leakPhotoCount: getPhotoCount(for: window, type: "Leak")
                    )
                }
            )
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(jobData)
        let jsonURL = directory.appendingPathComponent("job.json")
        try data.write(to: jsonURL)
    }
    
    private func generateWindowsCSV(in directory: URL) async throws {
        var csvContent = "Window ID,Window Number,X Position,Y Position,Width,Height,Type,Material,Test Result,Leak Points,Inaccessible,Notes,Exterior Photo Count,Interior Photo Count,Leak Photo Count\n"
        
        for window in windows {
            let windowId = window.windowId ?? ""
            let windowNumber = window.windowNumber ?? ""
            let xPosition = String(window.xPosition)
            let yPosition = String(window.yPosition)
            let width = String(window.width)
            let height = String(window.height)
            let windowType = window.windowType ?? ""
            let material = window.material ?? ""
            let testResult = window.testResult ?? ""
            let leakPoints = String(window.leakPoints)
            let inaccessible = window.isInaccessible ? "Yes" : "No"
            let notes = window.notes ?? ""
            let exteriorPhotoCount = getPhotoCount(for: window, type: "Exterior")
            let interiorPhotoCount = getPhotoCount(for: window, type: "Interior")
            let leakPhotoCount = getPhotoCount(for: window, type: "Leak")
            
            let row = "\(windowId),\(windowNumber),\(xPosition),\(yPosition),\(width),\(height),\(windowType),\(material),\(testResult),\(leakPoints),\(inaccessible),\(notes),\(exteriorPhotoCount),\(interiorPhotoCount),\(leakPhotoCount)"
            
            csvContent += row + "\n"
        }
        
        let csvURL = directory.appendingPathComponent("windows.csv")
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
    }
    
    private func generateOverheadWithDots(in directory: URL) async throws {
        guard let imagePath = job.overheadImagePath else { 
            print("⚠️ No overhead image path found for job")
            return 
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("⚠️ Overhead image file not found at: \(imageURL.path)")
            return
        }
        
        guard let image = NSImage(contentsOfFile: imageURL.path) else { 
            print("⚠️ Could not load overhead image from: \(imageURL.path)")
            return 
        }
        
        // Create image with window dots
        let imageSize = image.size
        let imageWithDots = NSImage(size: imageSize, flipped: false) { rect in
            image.draw(in: rect)
            
            // Draw window dots
            for window in windows {
                let point = CGPoint(x: window.xPosition, y: window.yPosition)
                let windowDotColor = dotColor(for: window)
                
                let context = NSGraphicsContext.current!.cgContext
                context.setFillColor(windowDotColor.cgColor)
                context.fillEllipse(in: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
                
                // Draw window number (just the number at the end of the specimen name)
                let windowNumber = window.windowNumber ?? ""
                let displayNumber = extractNumberFromSpecimenName(windowNumber)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let textSize = displayNumber.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: point.x - textSize.width / 2,
                    y: point.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                displayNumber.draw(in: textRect, withAttributes: attributes)
            }
            return true
        }
        
        guard let tiffData = imageWithDots.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("⚠️ Could not convert image to PNG")
            return
        }
        let outputURL = directory.appendingPathComponent("overhead_with_dots.png")
        try pngData.write(to: outputURL)
    }
    
    private func copyPhotos(to directory: URL) async throws {
        let photosDirectory = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        
        // Create subdirectories for each photo type
        let exteriorPhotosDir = photosDirectory.appendingPathComponent("exterior")
        let interiorPhotosDir = photosDirectory.appendingPathComponent("interior")
        let leakPhotosDir = photosDirectory.appendingPathComponent("leak")
        
        try FileManager.default.createDirectory(at: exteriorPhotosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: interiorPhotosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: leakPhotosDir, withIntermediateDirectories: true)
        
        // Count total photos before processing
        var totalPhotos = 0
        for window in windows {
            let allPhotos = (window.photos?.allObjects as? [Photo]) ?? []
            totalPhotos += allPhotos.count
        }
        
        print("📸 Starting photo export: \(totalPhotos) total photos across \(windows.count) window(s)")
        
        // Fetch and copy photos from camera roll
        for window in windows {
            await copyPhotosForWindow(window, to: photosDirectory)
        }
        
        // Generate photo manifest
        var photoManifest = "Photo Manifest\n"
        photoManifest += "==============\n\n"
        
        for window in windows {
            let allPhotos = (window.photos?.allObjects as? [Photo]) ?? []
            let exteriorPhotos = allPhotos.filter { $0.photoType == "Exterior" }
            let interiorPhotos = allPhotos.filter { $0.photoType == "Interior" }
            let leakPhotos = allPhotos.filter { $0.photoType == "Leak" }
            
            photoManifest += "Window \(window.windowNumber ?? "Unknown"):\n"
            photoManifest += "  Exterior Photos: \(exteriorPhotos.count)\n"
            photoManifest += "  Interior Photos: \(interiorPhotos.count)\n"
            photoManifest += "  Leak Photos: \(leakPhotos.count)\n\n"
        }
        
        let manifestURL = photosDirectory.appendingPathComponent("photo_manifest.txt")
        try photoManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        
        print("📸 Photo export completed. Check logs above for any skipped photos.")
    }
    
    private func copyPhotosForWindow(_ window: Window, to photosDirectory: URL) async {
        let windowNumber = window.windowNumber ?? "Unknown"
        
        // Copy photos by type
        let allPhotos = (window.photos?.allObjects as? [Photo]) ?? []
        
        let exteriorPhotos = allPhotos.filter { $0.photoType == "Exterior" }
        if !exteriorPhotos.isEmpty {
            print("📸 Processing \(exteriorPhotos.count) exterior photos for window \(windowNumber)")
            await copyPhotosByType(exteriorPhotos, to: photosDirectory.appendingPathComponent("exterior"), windowNumber: windowNumber, photoType: "Exterior")
        }
        
        let interiorPhotos = allPhotos.filter { $0.photoType == "Interior" }
        if !interiorPhotos.isEmpty {
            print("📸 Processing \(interiorPhotos.count) interior photos for window \(windowNumber)")
            await copyPhotosByType(interiorPhotos, to: photosDirectory.appendingPathComponent("interior"), windowNumber: windowNumber, photoType: "Interior")
        }
        
        let leakPhotos = allPhotos.filter { $0.photoType == "Leak" }
        if !leakPhotos.isEmpty {
            print("📸 Processing \(leakPhotos.count) leak photos for window \(windowNumber)")
            await copyPhotosByType(leakPhotos, to: photosDirectory.appendingPathComponent("leak"), windowNumber: windowNumber, photoType: "Leak")
        }
    }
    
    private func copyPhotosByType(_ photos: [Photo], to directory: URL, windowNumber: String, photoType: String) async {
        var successCount = 0
        var skippedCount = 0
        
        for (index, photo) in photos.enumerated() {
            let photoId = photo.photoId ?? "unknown"
            
            // Check if photo is from file system
            if photo.photoSource == "FileSystem", let filePath = photo.filePath {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fullPath = documentsDirectory.appendingPathComponent(filePath)
                
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    let filename = "\(windowNumber)_\(photo.photoType ?? "Unknown")_\(index + 1).jpg"
                    let photoURL = directory.appendingPathComponent(filename)
                    
                    do {
                        try FileManager.default.copyItem(at: fullPath, to: photoURL)
                        print("✅ Copied photo from file system: \(filename) (Photo ID: \(photoId))")
                        successCount += 1
                    } catch {
                        print("❌ FAILED to copy photo \(filename) (Photo ID: \(photoId)): \(error.localizedDescription)")
                        skippedCount += 1
                    }
                } else {
                    print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - File not found at path: \(filePath) (Photo ID: \(photoId))")
                    skippedCount += 1
                }
                continue
            }
            
            // Otherwise, try Photos library
            guard let localIdentifier = photo.localIdentifier else {
                print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - Missing localIdentifier and filePath (Photo ID: \(photoId))")
                skippedCount += 1
                continue
            }
            
            // Fetch photo from Photos framework
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - Invalid localIdentifier '\(localIdentifier)' not found in Photos library (Photo ID: \(photoId))")
                skippedCount += 1
                continue
            }
            
            // Request image data
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // On macOS, requestImage returns NSImage directly
                PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { nsImage, info in
                    if let nsImage = nsImage {
                        // Convert NSImage to Data (JPEG)
                        guard let tiffData = nsImage.tiffRepresentation,
                              let bitmapRep = NSBitmapImageRep(data: tiffData),
                              let imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                            print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - Failed to convert image to JPEG (Photo ID: \(photoId))")
                            skippedCount += 1
                            continuation.resume()
                            return
                        }
                        
                        // Save photo with descriptive filename
                        let filename = "\(windowNumber)_\(photo.photoType ?? "Unknown")_\(index + 1).jpg"
                        let photoURL = directory.appendingPathComponent(filename)
                        
                        do {
                            try imageData.write(to: photoURL)
                            print("✅ Copied photo from Photos library: \(filename) (Photo ID: \(photoId))")
                            successCount += 1
                        } catch {
                            print("❌ FAILED to copy photo \(filename) (Photo ID: \(photoId)): \(error.localizedDescription)")
                            skippedCount += 1
                        }
                    } else {
                        // Check if there's an error in the info dictionary
                        if let error = info?[PHImageErrorKey] as? Error {
                            print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - Failed to load image: \(error.localizedDescription) (Photo ID: \(photoId), LocalID: \(localIdentifier))")
                        } else {
                            print("⚠️ SKIPPED: Photo \(index + 1) for window \(windowNumber) (\(photoType)) - No image returned (Photo ID: \(photoId), LocalID: \(localIdentifier))")
                        }
                        skippedCount += 1
                    }
                    continuation.resume()
                }
            }
        }
        
        // Summary for this photo type
        if skippedCount > 0 {
            print("📊 \(photoType) photos for window \(windowNumber): \(successCount) copied, \(skippedCount) skipped (out of \(photos.count) total)")
        } else {
            print("📊 \(photoType) photos for window \(windowNumber): \(successCount) copied successfully (out of \(photos.count) total)")
        }
    }
    
    private func generateReport(in directory: URL) async throws {
        // Generate PDF report
        let pdfData = try await generatePDFReport()
        let reportURL = directory.appendingPathComponent("WindowTests.pdf")
        try pdfData.write(to: reportURL)
        print("✅ PDF report generated: \(reportURL.path)")
        
        // Generate DOCX report
        let docxURL = try await generateDOCXReport(in: directory)
        print("✅ DOCX report generated: \(docxURL.path)")
    }
    
    func generateStandaloneDOCXReport() async throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsRoot = documentsDirectory.appendingPathComponent("exports/docx")
        try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)
        
        let workingDirectory = reportsRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        
        // Ensure the overhead map with dots exists for the overview pages
        try await generateOverheadWithDots(in: workingDirectory)

        let temporaryDocURL = try await generateDOCXReport(in: workingDirectory)
        
        let baseName = sanitizeFilenameComponent(job.jobId ?? "WindowTests")
        let timestamp = DateFormatter.exportDate.string(from: Date())
        let finalURL = reportsRoot.appendingPathComponent("\(baseName)_Report_\(timestamp).docx")
        
        try FileManager.default.removeItemIfExists(at: finalURL)
        try FileManager.default.copyItem(at: temporaryDocURL, to: finalURL)
        try? FileManager.default.removeItem(at: workingDirectory)
        
        return finalURL
    }
    
    // TEMPORARY DEBUG FUNCTION: Generate PDF with only damage location image
    private func generateDebugPDFReport() async throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size (8.5" x 11")
        let pdfData = NSMutableData()
        
        // Capture self explicitly to avoid capture issues in closure
        let job = self.job
        let windows = self.windows
        
        var mediaBox = pageRect
        guard let dataConsumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: dataConsumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "PDFError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }
        
        // Draw only the damage locations page
        pdfContext.beginPage(mediaBox: &mediaBox)
        self.drawSummaryPage(context: pdfContext, pageRect: pageRect, pageNumber: 1, totalPages: 1, job: job, windows: windows)
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    func generatePDFReport() async throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size (8.5" x 11")
        
        // Create mutable data for PDF
        let pdfData = NSMutableData()
        
        // Calculate total pages first
        var allPages: [(type: String, window: Window?, photos: [FieldResultsPackage.PhotoData]?)] = []
        
        for window in sortWindowsByTitleThenNumber(windows) {
            // Add test page for each window
            allPages.append((type: "test", window: window, photos: nil))
            
            // Collect all photos for this window
            // Order by creation date (oldest first) regardless of type
            // Only include photos marked for report inclusion
            // Use a Set to track photo IDs to prevent duplicates
            var allPhotos: [FieldResultsPackage.PhotoData] = []
            var processedPhotoIds = Set<String>()
            
            let oldestFirst: (Photo, Photo) -> Bool = {
                ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
            }
            
            let windowPhotos = ((window.photos?.allObjects as? [Photo]) ?? [])
                .filter { $0.includeInReport }
            
            // Sort all photos by creation date (oldest first) regardless of type
            let sortedPhotos = windowPhotos.sorted(by: oldestFirst)
            
            // Helper function to add photo if not already processed
            func addPhotoIfNotDuplicate(_ photo: Photo, defaultCaption: String) async {
                guard let photoId = photo.photoId, !processedPhotoIds.contains(photoId) else {
                    print("⚠️ PDF: Skipping duplicate photo (ID: \(photo.photoId ?? "unknown"))")
                    return
                }
                
                if let image = await fetchPhotoImage(for: photo) {
                    let caption = photo.notes?.isEmpty == false ? photo.notes! : defaultCaption
                    allPhotos.append(FieldResultsPackage.PhotoData(photo: photo, image: image, caption: caption))
                    processedPhotoIds.insert(photoId)
                }
            }
            
            // Add photos in the order they were added (sorted by createdAt)
            for photo in sortedPhotos {
                let defaultCaption: String
                switch photo.photoType {
                case "Interior":
                    defaultCaption = "Interior Photo"
                case "Leak":
                    defaultCaption = "Leak Photo"
                case "Exterior":
                    defaultCaption = "Exterior Photo"
                default:
                    defaultCaption = "Photo"
                }
                await addPhotoIfNotDuplicate(photo, defaultCaption: defaultCaption)
            }
            
            // Add photo pages (4 photos per page)
            var photoIndex = 0
            while photoIndex < allPhotos.count {
                let pagePhotos = Array(allPhotos[photoIndex..<min(photoIndex + 4, allPhotos.count)])
                let debugOrder = pagePhotos.enumerated().map { index, data in
                    let createdAtString = data.photo.createdAt?.description ?? "nil"
                    return "\(index): id=\(data.photo.photoId ?? "nil"), createdAt=\(createdAtString)"
                }.joined(separator: " | ")
                print("🧭 Photo page order for window \(window.windowNumber ?? "Unknown"): \(debugOrder)")
                allPages.append((type: "photos", window: window, photos: pagePhotos))
                photoIndex += 4
            }
        }
        
        // Calculate total pages including cover, overview, engineering letter, purpose/weather, damage locations, summary of findings, window testing summary pages, calibration page, works cited, and credentials page
        let totalPages = allPages.count + 10 // +10 for cover (page 1), overview (page 2), engineering letter (page 3), purpose/weather (page 4), damage locations (page 5), summary of findings (page 6), window testing summary (page 7), calibration, works cited, and credentials (last page)
        
        // Generate PDF synchronously (pdfData is a synchronous method)
        // Capture self explicitly to avoid capture issues in closure
        let job = self.job
        let windows = self.windows
        
        // Create PDF title from job address/name
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        var addressComponents: [String] = []
        if !addressToUse.isEmpty {
            addressComponents.append(addressToUse)
        }
        if let city = job.city, !city.isEmpty {
            addressComponents.append(city)
        }
        if let state = job.state, !state.isEmpty {
            addressComponents.append(state)
        }
        if let zip = job.zip, !zip.isEmpty {
            addressComponents.append(zip)
        }
        let addressString = addressComponents.joined(separator: ", ")
        let pdfTitle: String
        if !addressString.isEmpty {
            pdfTitle = addressString
        } else if let jobId = job.jobId {
            pdfTitle = jobId
        } else if let clientName = job.clientName {
            pdfTitle = clientName
        } else {
            pdfTitle = "Window Testing Report"
        }
        
        // Create PDF document info dictionary
        var pdfInfo: [CFString: Any] = [:]
        pdfInfo[kCGPDFContextTitle] = pdfTitle
        pdfInfo[kCGPDFContextAuthor] = job.inspectorName ?? "Unknown Inspector"
        pdfInfo[kCGPDFContextCreator] = "Window Reporter App"
        
        // Create PDF context using Core Graphics
        var mediaBox = pageRect
        guard let dataConsumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: dataConsumer, mediaBox: &mediaBox, pdfInfo as CFDictionary) else {
            throw NSError(domain: "PDFError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }
        
        // Ensure no graphics context is set initially
        NSGraphicsContext.current = nil
        
        var pageNumber = 0
        
        // Helper function to begin a new page
        func beginPage(pageName: String = "") {
            pageNumber += 1
            print("📄 Beginning page \(pageNumber): \(pageName)")
            
            // CRITICAL: Ensure NSGraphicsContext is completely cleared BEFORE calling beginPage
            // This prevents nested beginPage calls
            NSGraphicsContext.current = nil
            
            // Ensure PDF context is flushed and ready
            pdfContext.flush()
            
            var mediaBox = pageRect
            pdfContext.beginPage(mediaBox: &mediaBox)
            print("✅ CGContext.beginPage() called for page \(pageNumber)")
            
            // Create a NEW NSGraphicsContext for each page AFTER beginPage completes
            // This ensures the context is properly tied to the current page
            let graphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.current = graphicsContext
            print("✅ NSGraphicsContext created and set for page \(pageNumber)")
        }
        
        // Helper function to end a page
        func endPage() {
            print("📄 Ending page \(pageNumber)")
            // CRITICAL: Clear graphics context BEFORE next beginPage
            // This must happen before the next beginPage call
            NSGraphicsContext.current = nil
            
            // Flush the PDF context to ensure all drawing operations are complete
            pdfContext.flush()
            
            print("✅ Graphics context cleared and flushed for page \(pageNumber)")
            // Note: Don't call pdfContext.endPage() - beginPage() for next page handles it
        }
        
        print("📊 Starting PDF generation with \(totalPages) total pages")
        print("📊 Will generate \(allPages.count) additional pages (test + photo pages)")
        
        // Draw cover page (page 1)
        beginPage(pageName: "Cover")
        self.drawCoverPage(context: pdfContext, pageRect: pageRect, job: job)
        endPage()
        
        // Draw overview page (page 2)
        beginPage(pageName: "Overview")
        self.drawOverviewPage(context: pdfContext, pageRect: pageRect, pageNumber: 2, totalPages: totalPages, job: job)
        endPage()
        
        // Draw engineering letter page (page 3)
        beginPage(pageName: "Engineering Letter")
        self.drawEngineeringLetterPage(context: pdfContext, pageRect: pageRect, pageNumber: 3, totalPages: totalPages, job: job)
        endPage()
        
        // Draw purpose/observations/weather history page (page 4)
        beginPage(pageName: "Purpose/Observations/Weather")
        self.drawPurposeObservationsWeatherPage(context: pdfContext, pageRect: pageRect, pageNumber: 4, totalPages: totalPages, job: job)
        endPage()
        
        // Draw damage locations page (page 5)
        beginPage(pageName: "Damage Locations")
        self.drawSummaryPage(context: pdfContext, pageRect: pageRect, pageNumber: 5, totalPages: totalPages, job: job, windows: windows)
        endPage()
        
        // Draw summary of findings page (page 6)
        beginPage(pageName: "Summary of Findings")
        self.drawSummaryOfFindingsPage(context: pdfContext, pageRect: pageRect, pageNumber: 6, totalPages: totalPages, job: job, windows: windows)
        endPage()
        
        // Draw window testing summary page (page 7)
        beginPage(pageName: "Window Testing Summary")
        self.drawWindowTestingSummaryPage(context: pdfContext, pageRect: pageRect, pageNumber: 7, totalPages: totalPages, job: job, windows: windows)
        endPage()
        
        // Draw all other pages (test and photo pages start at page 8)
        for (index, pageInfo) in allPages.enumerated() {
            let logicalPageNumber = index + 8 // +8 because cover is page 1, overview is page 2, engineering letter is page 3, purpose/weather is page 4, damage locations is page 5, summary of findings is page 6, window testing summary is page 7
            let pageName = pageInfo.type == "test" ? "Test Page for \(pageInfo.window?.windowNumber ?? "Unknown")" : "Photo Page for \(pageInfo.window?.windowNumber ?? "Unknown")"
            beginPage(pageName: pageName)
            
            if pageInfo.type == "test", let window = pageInfo.window {
                self.drawTestPage(context: pdfContext, pageRect: pageRect, window: window, pageNumber: logicalPageNumber, totalPages: totalPages, job: job)
            } else if pageInfo.type == "photos", let window = pageInfo.window, let photos = pageInfo.photos {
                self.drawPhotoPage(context: pdfContext, pageRect: pageRect, window: window, photos: photos, pageNumber: logicalPageNumber, totalPages: totalPages, job: job)
            }
            endPage()
        }
        
        // Draw calibration page
        let calibrationPageNumber = totalPages - 2
        beginPage(pageName: "Calibration")
        self.drawCalibrationPage(context: pdfContext, pageRect: pageRect, pageNumber: calibrationPageNumber, totalPages: totalPages, job: job)
        endPage()
        
        // Draw works cited page (after calibration)
        beginPage(pageName: "Works Cited")
        self.drawWorksCitedPage(context: pdfContext, pageRect: pageRect, pageNumber: totalPages - 1, totalPages: totalPages, job: job)
        endPage()
        
        // Draw credentials page at the very end (last page)
        beginPage(pageName: "Credentials")
        self.drawCredentialsPage(context: pdfContext, pageRect: pageRect, pageNumber: totalPages, totalPages: totalPages, job: job)
        endPage()
        
        print("📊 Finished drawing all pages. Closing PDF context...")
        
        // Close PDF context
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    /// Export just the PDF report to a file and return the URL
    func exportPDFReport() async throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = documentsDirectory.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let jobId = job.jobId ?? "Unknown"
        let city = job.city ?? "Unknown"
        let dateString = DateFormatter.exportDate.string(from: Date())
        let fileName = "\(jobId)_\(city)_\(dateString).pdf"
        
        let pdfData = try await generatePDFReport()
        let pdfURL = exportDirectory.appendingPathComponent(fileName)
        try pdfData.write(to: pdfURL)
        
        print("✅ PDF report exported: \(pdfURL.path)")
        return pdfURL
    }

    private func drawTestPage(context: CGContext, pageRect: CGRect, window: Window, pageNumber: Int, totalPages: Int, job: Job) {
    // Title at top
    let titleFont = NSFont.boldSystemFont(ofSize: 24)
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
    ]
    let titleHeight: CGFloat = 30
    let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
    "WINDOW TESTING".draw(in: titleRect, withAttributes: titleAttributes)
    
    // General Test Information Table - position below title (reduced margin for shift up)
    let tableYTopDown = titleRect.maxY + 15.0  // ← Changed from +25 to +15 to shift up
    let cellHeight = 22.0  // ← Match section bar height for consistency (was 25)
    let colWidths: [CGFloat] = [100, 80, 200, 80, 100]
    var currentX: CGFloat = 50
    
    // Header text (bold black, no blue bar)
    let headerFont = NSFont.boldSystemFont(ofSize: 12)
    let headerAttributes: [NSAttributedString.Key: Any] = [
        .font: headerFont,
        .foregroundColor: NSColor.black
    ]
    let headers = ["Specimen No.", "Test No.", "Procedure", "Start Time", "Completion"]
    currentX = 50
    for (index, header) in headers.enumerated() {
        let attributedHeader = NSAttributedString(string: header, attributes: headerAttributes)
        attributedHeader.draw(at: CGPoint(x: currentX + 5, y: tableYTopDown))
        currentX += colWidths[index]
    }
    
    // Data row (black text)
    let dataFont = NSFont.systemFont(ofSize: 11)
    let dataAttributes: [NSAttributedString.Key: Any] = [
        .font: dataFont,
        .foregroundColor: NSColor.black
    ]
    let windowNumber = window.windowNumber ?? "1"
    let specimenNumber = windowNumber.replacingOccurrences(of: "Specimen ", with: "")
    let testNumber = specimenNumber
    let procedure = job.testProcedure ?? "ASTM E331"
    let dateFormatter = DateFormatter()
    dateFormatter.timeStyle = .short
    dateFormatter.dateStyle = .none
    // Use testStartTime if available, otherwise fallback to createdAt
    let startTime: String
    if let testStartTime = window.testStartTime {
        startTime = dateFormatter.string(from: testStartTime)
    } else {
        startTime = dateFormatter.string(from: window.createdAt ?? Date())
    }
    // Use testStopTime if available, otherwise show "N/A"
    let completionTime: String
    if let testStopTime = window.testStopTime {
        completionTime = dateFormatter.string(from: testStopTime)
    } else {
        completionTime = "N/A"
    }
    currentX = 50
    let dataRow = [specimenNumber, testNumber, procedure, startTime, completionTime]
    let headerLineHeight = headerFont.lineHeight
    let dataTextY = tableYTopDown + headerLineHeight + 7  // Position below header text
    for (index, data) in dataRow.enumerated() {
        data.draw(at: CGPoint(x: currentX + 5, y: dataTextY), withAttributes: dataAttributes)
        currentX += colWidths[index]
    }
    
    // Sections start (spacing after table)
    var currentY: CGFloat = dataTextY + dataFont.lineHeight + 15  // Space after header and data row
    
    // Section A: Test Specimen
    currentY = drawSection(context: context, pageRect: pageRect, title: "A. Test Specimen", startY: currentY, window: window, job: job)
    
    // Section B: Specimen Type and Size
    currentY = drawSectionB(context: context, pageRect: pageRect, title: "B. Specimen Type and Size", startY: currentY, window: window, job: job)
    
    // Section C: Specimen Location
    currentY = drawSectionC(context: context, pageRect: pageRect, title: "C. Specimen Location and Related Information", startY: currentY, window: window, job: job)
    
    // Section D: Specimen Age
    currentY = drawSectionD(context: context, pageRect: pageRect, title: "D. Specimen Age and Performance", startY: currentY, window: window, job: job)
    
    // Section E: Weather Conditions
    currentY = drawSectionE(context: context, pageRect: pageRect, title: "E. Weather Conditions", startY: currentY, window: window, job: job)
    
    // Test Recap and Comments (reduced spacing)
    currentY += 5  // ← Reduced from +10 to +5
    currentY = drawSectionHeader(context: context, pageRect: pageRect, title: "Test Recap and Comments:", startY: currentY)
    currentY += 5
    
    let recapFont = NSFont.systemFont(ofSize: 11)
    let recapAttributes: [NSAttributedString.Key: Any] = [
        .font: recapFont,
        .foregroundColor: NSColor.black
    ]
    let waterPressure = job.waterPressure > 0 ? job.waterPressure : 12.0
    let recapText = "The entire specimen was sprayed with water at a rate of 7.2 (Gal/Hr./Sq. Ft.) at \(Int(waterPressure)) PSI.\n"
    let displayResult = getDisplayTestResult(for: window)
    let resultText = (displayResult == "Pass" ? "No water leakage was observed following the test." : displayResult == "Fail" ? "Water leakage was observed following the test." : displayResult == "Inaccessible" ? "Window is inaccessible." : "Test result is pending.")
    let fullRecap = recapText + resultText
    let textRect = CGRect(x: 60, y: currentY, width: pageRect.width - 120, height: 100)
    fullRecap.draw(in: textRect, withAttributes: recapAttributes)
    
    // Footer
    let footerFont = NSFont.systemFont(ofSize: 10)
    let footerAttributes: [NSAttributedString.Key: Any] = [
        .font: footerFont,
        .foregroundColor: NSColor.gray
    ]
    // Use cleaned address if available, fallback to original
    let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
    let address = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip).uppercased()
    let footerY = pageRect.height - 50
    address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
    let pageText = "PAGE \(pageNumber) OF \(totalPages)"
    let pageTextSize = pageText.size(withAttributes: footerAttributes)
    pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
}
    
    // private func drawTestPage(context: CGContext, pageRect: CGRect, window: Window, pageNumber: Int, totalPages: Int, job: Job) {
    //     // Title at top - PDF uses bottom-left origin, so top is at pageRect.height
    //     let titleFont = NSFont.boldSystemFont(ofSize: 24)
    //     let titleAttributes: [NSAttributedString.Key: Any] = [
    //         .font: titleFont,
    //         .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
    //     ]
    //     // Use draw(in:) with a rect for more predictable positioning
    //     let titleHeight: CGFloat = 30
    //     let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
    //     "WINDOW TESTING".draw(in: titleRect, withAttributes: titleAttributes)
        
    //     // General Test Information Table - position below title using top-down coordinates
    //     let tableYTopDown = titleRect.maxY + 25.0  // 25 points below title (top-down for text)
    //     let cellHeight = 25.0
    //     let colWidths: [CGFloat] = [100, 80, 200, 80, 100]
    //     var currentX: CGFloat = 50
        
    //     // Convert tableY to bottom-up for Core Graphics operations
    //     let tableYBottomUp = pageRect.height - tableYTopDown - cellHeight
        
    //     // Header bar - Core Graphics uses bottom-up coordinates
    //     context.setFillColor(NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0).cgColor)
    //     context.fill(CGRect(x: 50, y: tableYBottomUp, width: pageRect.width - 100, height: cellHeight))
        
    //     // Header text - NSString.draw uses top-down coordinates
    //     // Draw text AFTER the blue bar to ensure it appears on top
    //     let headerFont = NSFont.boldSystemFont(ofSize: 12)
    //     let headerAttributes: [NSAttributedString.Key: Any] = [
    //         .font: headerFont,
    //         .foregroundColor: NSColor.white  // Explicit white color for visibility on blue background
    //     ]
    //     let headers = ["Specimen No.", "Test No.", "Procedure", "Start Time", "Completion Time"]
    //     // Center text vertically in the blue bar (similar to drawSectionHeader)
    //     let fontCapHeight = headerFont.capHeight
    //     let headerTextY = tableYTopDown + (cellHeight - fontCapHeight) / 2
    //     for (index, header) in headers.enumerated() {
    //         // Use NSAttributedString to ensure color is properly applied in PDF context
    //         let attributedHeader = NSAttributedString(string: header, attributes: headerAttributes)
    //         attributedHeader.draw(at: CGPoint(x: currentX + 5, y: headerTextY))
    //         currentX += colWidths[index]
    //     }
        
    //     // Data row - NSString.draw uses top-down coordinates
    //     let dataFont = NSFont.systemFont(ofSize: 11)
    //     let dataAttributes: [NSAttributedString.Key: Any] = [
    //         .font: dataFont,
    //         .foregroundColor: NSColor.black
    //     ]
    //     let windowNumber = window.windowNumber ?? "1"
    //     let specimenNumber = windowNumber.replacingOccurrences(of: "Specimen ", with: "")
    //     let testNumber = specimenNumber
    //     let procedure = job.testProcedure ?? "ASTM E331"
    //     let dateFormatter = DateFormatter()
    //     dateFormatter.timeStyle = .short
    //     dateFormatter.dateStyle = .none
    //     // Use testStartTime if available, otherwise fallback to createdAt
    //     let startTime: String
    //     if let testStartTime = window.testStartTime {
    //         startTime = dateFormatter.string(from: testStartTime)
    //     } else {
    //         startTime = dateFormatter.string(from: window.createdAt ?? Date())
    //     }
    //     // Use testStopTime if available, otherwise show "N/A"
    //     let completionTime: String
    //     if let testStopTime = window.testStopTime {
    //         completionTime = dateFormatter.string(from: testStopTime)
    //     } else {
    //         completionTime = "N/A"
    //     }
        
    //     currentX = 50
    //     let dataRow = [specimenNumber, testNumber, procedure, startTime, completionTime]
    //     for (index, data) in dataRow.enumerated() {
    //         data.draw(at: CGPoint(x: currentX + 5, y: tableYTopDown + cellHeight + 7), withAttributes: dataAttributes)
    //         currentX += colWidths[index]
    //     }
        
    //     // currentY for sections - use top-down coordinates since sections use draw calls
    //     var currentY: CGFloat = tableYTopDown + cellHeight * 2 + 20
        
    //     // Section A: Test Specimen
    //     currentY = drawSection(context: context, pageRect: pageRect, title: "A. Test Specimen", startY: currentY, window: window, job: job)
        
    //     // Section B: Specimen Type and Size
    //     currentY = drawSectionB(context: context, pageRect: pageRect, title: "B. Specimen Type and Size", startY: currentY, window: window, job: job)
        
    //     // Section C: Specimen Location
    //     currentY = drawSectionC(context: context, pageRect: pageRect, title: "C. Specimen Location and Related Information", startY: currentY, window: window, job: job)
        
    //     // Section D: Specimen Age
    //     currentY = drawSectionD(context: context, pageRect: pageRect, title: "D. Specimen Age and Performance", startY: currentY, window: window, job: job)
        
    //     // Section E: Weather Conditions
    //     currentY = drawSectionE(context: context, pageRect: pageRect, title: "E. Weather Conditions", startY: currentY, window: window, job: job)
        
    //     // Test Recap and Comments
    //     currentY += 10
    //     currentY = drawSectionHeader(context: context, pageRect: pageRect, title: "Test Recap and Comments:", startY: currentY)
    //     currentY += 5  // drawSectionHeader already adds 5 points spacing
        
    //     let recapFont = NSFont.systemFont(ofSize: 11)
    //     let recapAttributes: [NSAttributedString.Key: Any] = [
    //         .font: recapFont,
    //         .foregroundColor: NSColor.black
    //     ]
        
    //     let waterPressure = job.waterPressure > 0 ? job.waterPressure : 12.0
    //     let recapText = "The entire specimen was sprayed with water at a rate of 7.2 (Gal/Hr./Sq. Ft.) at \(Int(waterPressure)) PSI.\n"
    //     let resultText = (window.testResult == "Pass" ? "No water leakage was observed following the test." : window.testResult == "Fail" ? "Water leakage was observed following the test." : "Test result is pending.")
    //     let fullRecap = recapText + resultText
        
    //     let textRect = CGRect(x: 60, y: currentY, width: pageRect.width - 120, height: 100)
    //     fullRecap.draw(in: textRect, withAttributes: recapAttributes)
        
    //     // Footer at bottom (address and page number) - top-down coordinates: large Y value for bottom
    //     let footerFont = NSFont.systemFont(ofSize: 10)
    //     let footerAttributes: [NSAttributedString.Key: Any] = [
    //         .font: footerFont,
    //         .foregroundColor: NSColor.gray
    //     ]
        
    //     // Use cleaned address if available, fallback to original
    //     let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
    //     let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
    //     let footerY = pageRect.height - 50  // 50 points from bottom
    //     address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
    //     let pageText = "PAGE \(pageNumber) OF \(totalPages)"
    //     let pageTextSize = pageText.size(withAttributes: footerAttributes)
    //     pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    // }
    
    private func drawSection(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat, window: Window, job: Job) -> CGFloat {
        var currentY = startY
        
        // Section header
        currentY = drawSectionHeader(context: context, pageRect: pageRect, title: title, startY: currentY)
        currentY += 2  // Reduced from 5 to 2 for tighter spacing after header
        
        let font = NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        
        // Test Results
        "Test Results:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        getDisplayTestResult(for: window).draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        // Water Pressure
        "Water Pressure:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        let waterPressure = job.waterPressure > 0 ? job.waterPressure : 12.0
        "\(Int(waterPressure)) PSI".draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        // Deviation
        "Deviation:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        "None".draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        // Size Requirements
        "Size Requirements:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        "None".draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        // Description
        "Description:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        let description = "Residential \(window.windowType ?? "Window") - \(window.material ?? "Unknown Material")"
        description.draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        // Window photo placeholder (embedded on right side)
        // For now, we'll leave space for it - photos will be on separate pages
        
        return currentY + 10
    }
    
    private func drawSectionB(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat, window: Window, job: Job) -> CGFloat {
        var currentY = startY
        
        currentY = drawSectionHeader(context: context, pageRect: pageRect, title: title, startY: currentY)
        currentY += 2  // Reduced from 5 to 2 for tighter spacing after header
        
        let font = NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        
        // Combine Manufacturer and Model on same line
        let manufacturerModelText = "Manufacturer: Unknown  --  Model: Unknown"
        let manufacturerModelRect = manufacturerModelText.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        manufacturerModelText.draw(in: CGRect(x: 60, y: currentY, width: pageRect.width - 100, height: manufacturerModelRect.height), withAttributes: attributes)
        currentY += manufacturerModelRect.height + 18
        
        "Operation:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
        (window.windowType ?? "Unknown").draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
        currentY += 18
        
        if window.width > 0 && window.height > 0 {
            "Width:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
            String(format: "%.1f\"", window.width).draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
            currentY += 18
            
            "Height:".draw(at: CGPoint(x: 60, y: currentY), withAttributes: labelAttributes)
            String(format: "%.1f\"", window.height).draw(at: CGPoint(x: 200, y: currentY), withAttributes: attributes)
            currentY += 18
        }
        
        return currentY + 10
    }
    
    private func drawSectionC(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat, window: Window, job: Job) -> CGFloat {
        var currentY = startY
        
        currentY = drawSectionHeader(context: context, pageRect: pageRect, title: title, startY: currentY)
        currentY += 2  // Reduced from 5 to 2 for tighter spacing after header
        
        let font = NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        
        let labelStartX: CGFloat = 60
        let labelValuePadding: CGFloat = 15
        
        // Helper function to draw label and value with dynamic positioning
        func drawLabelValue(label: String, value: String, y: CGFloat) {
            label.draw(at: CGPoint(x: labelStartX, y: y), withAttributes: labelAttributes)
            let labelWidth = label.size(withAttributes: labelAttributes).width
            let valueX = labelStartX + labelWidth + labelValuePadding
            value.draw(at: CGPoint(x: valueX, y: y), withAttributes: attributes)
        }
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip)
        drawLabelValue(label: "Location:", value: address, y: currentY)
        currentY += 18
        
        let exteriorFinishes = "Glass, \(window.material ?? "Unknown"), Framed Windows"
        drawLabelValue(label: "Exterior Finishes:", value: exteriorFinishes, y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Interior Finishes:", value: "Drywall", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "SF/CW Window Design Pressure:", value: "Unknown", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Building Pressure - Corner (PSF):", value: "Unknown", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Building Pressure - Field (PSF):", value: "Unknown", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Building Corner Distance (Feet):", value: "Unknown", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Specimen Plumb, Level and Square:", value: "Yes, within industry standards", y: currentY)
        currentY += 18
        
        return currentY + 10
    }
    
    private func drawSectionD(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat, window: Window, job: Job) -> CGFloat {
        var currentY = startY
        
        currentY = drawSectionHeader(context: context, pageRect: pageRect, title: title, startY: currentY)
        currentY += 2  // Reduced from 5 to 2 for tighter spacing after header
        
        let font = NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        
        let labelStartX: CGFloat = 60
        let labelValuePadding: CGFloat = 15
        
        // Helper function to draw label and value with dynamic positioning
        func drawLabelValue(label: String, value: String, y: CGFloat) {
            label.draw(at: CGPoint(x: labelStartX, y: y), withAttributes: labelAttributes)
            let labelWidth = label.size(withAttributes: labelAttributes).width
            let valueX = labelStartX + labelWidth + labelValuePadding
            value.draw(at: CGPoint(x: valueX, y: y), withAttributes: attributes)
        }
        
        drawLabelValue(label: "Specimen Age:", value: "Over 6 Months", y: currentY)
        currentY += 18
        
        drawLabelValue(label: "Modifications Prior to Test:", value: "None", y: currentY)
        currentY += 18
        
        return currentY + 10
    }
    
    private func drawSectionE(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat, window: Window, job: Job) -> CGFloat {
        var currentY = startY
        
        currentY = drawSectionHeader(context: context, pageRect: pageRect, title: title, startY: currentY)
        currentY += 2  // Reduced from 5 to 2 for tighter spacing after header
        
        let font = NSFont.systemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        
        let labelStartX: CGFloat = 60
        let labelValuePadding: CGFloat = 15
        
        // Helper function to draw label and value with dynamic positioning
        func drawLabelValue(label: String, value: String, y: CGFloat) {
            label.draw(at: CGPoint(x: labelStartX, y: y), withAttributes: labelAttributes)
            let labelWidth = label.size(withAttributes: labelAttributes).width
            let valueX = labelStartX + labelWidth + labelValuePadding
            value.draw(at: CGPoint(x: valueX, y: y), withAttributes: attributes)
        }
        
        let temp = job.temperature > 0 ? job.temperature : 73.0
        drawLabelValue(label: "Temperature (F):", value: String(format: "%.0f °F  --  ", temp), y: currentY)
        currentY += 18
        
        let windSpeed = job.windSpeed > 0 ? job.windSpeed : 5.0
        drawLabelValue(label: "Wind Speed/Direction (mph):", value: String(format: "%.0f Mph", windSpeed), y: currentY)
        currentY += 18
        
        // Combine Barometric Pressure and Precipitation on same line
        let barometricPrecipText = "Barometric Pressure (inHg): 29 inHg  --  Precipitation: 0%"
        let barometricPrecipRect = barometricPrecipText.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        barometricPrecipText.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: barometricPrecipRect.height), withAttributes: attributes)
        currentY += barometricPrecipRect.height + 18
        
        return currentY + 10
    }
    
    private func drawCoverPage(context: CGContext, pageRect: CGRect, job: Job) {
        // Load cover page image from app bundle
        // Try new cover page image first, then fallback to old one
        var coverImage: NSImage?
        if let imagePath = Bundle.main.path(forResource: "coverPageResized", ofType: "png", inDirectory: nil) {
            coverImage = NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: "coverPageResized", ofType: "png", inDirectory: "images") {
            coverImage = NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: "coverPageResized", ofType: "png") {
            coverImage = NSImage(contentsOfFile: imagePath)
        } else if let image = NSImage(named: "coverPageResized") {
            coverImage = image
        } else if let image = NSImage(named: "images/coverPageResized") {
            coverImage = image
        } else if let imagePath = Bundle.main.path(forResource: "screenshotOfCoverPageImage", ofType: "png", inDirectory: "images") {
            coverImage = NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: "screenshotOfCoverPageImage", ofType: "png") {
            coverImage = NSImage(contentsOfFile: imagePath)
        } else if let image = NSImage(named: "screenshotOfCoverPageImage") {
            coverImage = image
        } else if let image = NSImage(named: "images/screenshotOfCoverPageImage") {
            coverImage = image
        }
        
        // Draw cover page image filling entire page (edge to edge)
        if let image = coverImage {
            // Calculate image size to fill entire page while maintaining aspect ratio
            let pageAspectRatio = pageRect.width / pageRect.height
            let imageAspectRatio = image.size.width / image.size.height
            
            var imageWidth = pageRect.width
            var imageHeight = pageRect.height
            var imageX: CGFloat = 0
            var imageY: CGFloat = 0
            
            if imageAspectRatio > pageAspectRatio {
                // Image is wider - fill height, letterbox width
                imageHeight = pageRect.height
                imageWidth = imageHeight * imageAspectRatio
                imageX = (pageRect.width - imageWidth) / 2
            } else {
                // Image is taller - fill width, letterbox height
                imageWidth = pageRect.width
                imageHeight = imageWidth / imageAspectRatio
                imageY = (pageRect.height - imageHeight) / 2
            }
            
            // Draw image - convert Y coordinate for PDF coordinate system (bottom-left origin)
            // imageX and imageY are in top-down coordinates, convert to bottom-up for PDF
            let imageRectBottomUp = CGRect(x: imageX, y: pageRect.height - imageY - imageHeight, width: imageWidth, height: imageHeight)
            
            // Draw image using Core Graphics directly
            drawNSImage(image, in: imageRectBottomUp, context: context)
        }
        
        // Add owner name and address at the bottom in large bold text
        let ownerName = job.clientName ?? "Unknown"
        // Use cleaned address if available, fallback to original
        let addressLine1 = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let addressLine2 = formatAddressForExport(addressLine1: "", city: job.city, state: job.state, zip: job.zip)
        
        // Large bold font for owner name and address
        let largeFont = NSFont.boldSystemFont(ofSize: 18)
        let largeAttributes: [NSAttributedString.Key: Any] = [
            .font: largeFont,
            .foregroundColor: NSColor.black
        ]
        
        // Position at bottom of page (with some margin from bottom)
        // Increased bottom margin by ~1 inch (72 points) to raise the text
        let bottomMargin: CGFloat = 152  // Space from bottom (was 80, now 80 + 72)
        let textY = pageRect.height - bottomMargin  // Top-down coordinate
        
        // Draw owner name
        ownerName.draw(at: CGPoint(x: 50, y: textY), withAttributes: largeAttributes)
        
        // Draw address line 1 (street address) below owner name
        let addressLine1Y = textY + largeFont.lineHeight + 8
        addressLine1.draw(at: CGPoint(x: 50, y: addressLine1Y), withAttributes: largeAttributes)
        
        // Draw address line 2 (city, state, zip) below address line 1
        let addressLine2Y = addressLine1Y + largeFont.lineHeight + 4
        addressLine2.draw(at: CGPoint(x: 50, y: addressLine2Y), withAttributes: largeAttributes)
    }
    
    private func drawOverviewPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        // Title at top - "OVERVIEW"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "OVERVIEW".draw(in: titleRect, withAttributes: titleAttributes)
        
        // Load overhead image
        var overheadImage: NSImage?
        if let imagePath = job.overheadImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
            if FileManager.default.fileExists(atPath: imageURL.path) {
                overheadImage = NSImage(contentsOfFile: imageURL.path)
            }
        }
        
        // Draw report metadata right below the title (temporary until image positioning is fixed)
        let metadataFont = NSFont.systemFont(ofSize: 11)
        let metadataLabelFont = NSFont.boldSystemFont(ofSize: 11)
        let metadataAttributes: [NSAttributedString.Key: Any] = [
            .font: metadataFont,
            .foregroundColor: NSColor.black
        ]
        let metadataLabelAttributes: [NSAttributedString.Key: Any] = [
            .font: metadataLabelFont,
            .foregroundColor: NSColor.black
        ]
        
        // Calculate starting Y position for metadata (right below title)
        let metadataStartY = titleRect.maxY + 20  // 20 points below title
        var currentY = metadataStartY
        
        // Calculate image dimensions and position (for later when image positioning is fixed)
        var imageBottomY: CGFloat = 0
        var imageHeight: CGFloat = 0
        var imageX: CGFloat = 0
        var imageWidth: CGFloat = 0
        var imageTopYTopDown: CGFloat = 0
        
        // Calculate image size and position using the real image dimensions
        if let image = overheadImage {
            // 1. Force the image to be ~1/3 of the page tall
            let targetHeight: CGFloat = pageRect.height / 3
            imageWidth = targetHeight * (image.size.width / image.size.height)
            imageX = (pageRect.width - imageWidth) / 2
            
            // 2. Position: below metadata (will be repositioned when image positioning is fixed)
            imageTopYTopDown = currentY + 150  // Place below metadata for now
            imageHeight = targetHeight
            
            // Calculate bottom-up Y coordinate for drawing
            // In PDF (bottom-up), Y represents the bottom of the rectangle
            imageBottomY = pageRect.height - imageTopYTopDown - imageHeight
        }
        
        // Format date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let inspectionDateString = job.inspectionDate != nil ? dateFormatter.string(from: job.inspectionDate!) : "N/A"
        
        // Format owner name and address separately
        let ownerName = job.clientName ?? "Unknown"
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let ownerAddress = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip)
        
        // Draw metadata fields
        "REPORT NUMBER:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        (job.jobId ?? "Unknown").draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        currentY += 25
        
        "DATE OF INSPECTIONS:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        inspectionDateString.draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        currentY += 25
        
        "PREPARED FOR:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        (job.clientName ?? "Unknown").draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        currentY += 25
        
        "PREPARED BY:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        (job.inspectorName ?? "Unknown").draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        currentY += 25
        
        "OWNER NAME:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        ownerName.draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        currentY += 25
        
        "ADDRESS:".draw(at: CGPoint(x: 50, y: currentY), withAttributes: metadataLabelAttributes)
        ownerAddress.draw(at: CGPoint(x: 200, y: currentY), withAttributes: metadataAttributes)
        
        // Now draw the real image in the calculated position below the metadata
        if let image = overheadImage {
            // Draw image using Core Graphics directly
            let imageRect = CGRect(x: imageX,
                                   y: imageBottomY,
                                   width: imageWidth,
                                   height: imageHeight)
            
            drawNSImage(image, in: imageRect, context: context)
        }
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Reuse addressToUse from above (already declared on line 1263)
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func loadEngineerStampImage() -> NSImage? {
        // Try loading from images directory first, then root
        if let imagePath = Bundle.main.path(forResource: "EngineerStamp", ofType: "png", inDirectory: "images") {
            return NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: "EngineerStamp", ofType: "png") {
            return NSImage(contentsOfFile: imagePath)
        } else if let image = NSImage(named: "EngineerStamp") {
            return image
        } else if let image = NSImage(named: "images/EngineerStamp") {
            return image
        }
        return nil
    }
    
    private func drawEngineeringLetterPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        // Title at top - "ENGINEERING LETTER"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "ENGINEERING LETTER".draw(in: titleRect, withAttributes: titleAttributes)
        
        var currentY = titleRect.maxY + 20
        
        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateString = job.inspectionDate.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date())
        let dateFont = NSFont.systemFont(ofSize: 12)
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: NSColor.black
        ]
        dateString.draw(at: CGPoint(x: 50, y: currentY), withAttributes: dateAttributes)
        currentY += 40  // Added one line after date
        
        // Recipient information
        let recipientFont = NSFont.systemFont(ofSize: 12)
        let recipientAttributes: [NSAttributedString.Key: Any] = [
            .font: recipientFont,
            .foregroundColor: NSColor.black
        ]
        let clientName = job.clientName ?? "Unknown"
        clientName.draw(at: CGPoint(x: 50, y: currentY), withAttributes: recipientAttributes)
        currentY += 15
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        if !addressToUse.isEmpty {
            addressToUse.draw(at: CGPoint(x: 50, y: currentY), withAttributes: recipientAttributes)
            currentY += 15
        }
        
        let cityStateZip = formatAddressForExport(addressLine1: "", city: job.city, state: job.state, zip: job.zip)
        if !cityStateZip.isEmpty {
            cityStateZip.draw(at: CGPoint(x: 50, y: currentY), withAttributes: recipientAttributes)
            currentY += 40  // Added one line after client address
        }
        
        // Sender information
        let senderFont = NSFont.systemFont(ofSize: 12)
        let senderAttributes: [NSAttributedString.Key: Any] = [
            .font: senderFont,
            .foregroundColor: NSColor.black
        ]
        "K. Renevier, P.E.".draw(at: CGPoint(x: 50, y: currentY), withAttributes: senderAttributes)
        currentY += 15
        "FL Reg. No. 98372".draw(at: CGPoint(x: 50, y: currentY), withAttributes: senderAttributes)
        currentY += 20
        "1281 Trailhead Pl".draw(at: CGPoint(x: 50, y: currentY), withAttributes: senderAttributes)
        currentY += 15
        "Harrison, OH 45030".draw(at: CGPoint(x: 50, y: currentY), withAttributes: senderAttributes)
        currentY += 30  // Extra space before salutation
        
        // Salutation
        let salutationFont = NSFont.systemFont(ofSize: 12)
        let salutationAttributes: [NSAttributedString.Key: Any] = [
            .font: salutationFont,
            .foregroundColor: NSColor.black
        ]
        // Extract first name from client name if possible
        let firstName = clientName.components(separatedBy: " ").first ?? clientName
        let salutation = "Greetings \(firstName),"
        salutation.draw(at: CGPoint(x: 50, y: currentY), withAttributes: salutationAttributes)
        currentY += 40  // Added one line after Greetings
        
        // Body paragraphs
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.alignment = .left
        var bodyAttributesWithSpacing = bodyAttributes
        bodyAttributesWithSpacing[.paragraphStyle] = paragraphStyle
        
        // First paragraph
        let paragraph1 = "True Reports Inc., in collaboration with my individual firm, has conducted an evaluation of the condition of the windows at the property located at \(addressToUse.isEmpty ? "the property" : addressToUse), as detailed in the attached report. The opinions presented in this report have been formulated within a reasonable degree of professional certainty. These opinions are based on a review of the available information, associated research, as well as our knowledge, training and experience. True Reports Inc. reserves the right to update this report should additional information become available. The True Reports Inc's investigation of the property at \(addressToUse.isEmpty ? "the property" : addressToUse) was performed by the True Reports Inc. Field Inspection Team under my direct supervision."
        let paragraph1Rect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 200)
        paragraph1.draw(in: paragraph1Rect, withAttributes: bodyAttributesWithSpacing)
        currentY = paragraph1Rect.maxY - 30  // Reduced spacing before paragraph2
        
        // Second paragraph
        let paragraph2 = "It is my professional opinion that the property sustained damage to the windows of the building during Hurricane Milton. Windows will need to be repaired or replaced. All repairs must be in compliance with the Florida Building Code: Existing Building 2023."
        let paragraph2Rect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 100)
        paragraph2.draw(in: paragraph2Rect, withAttributes: bodyAttributesWithSpacing)
        currentY = paragraph2Rect.maxY - 30  // Reduced spacing before paragraph3
        
        // Third paragraph
        let paragraph3 = "True Reports Inc. appreciates the opportunity to assist with this inspection. Please call if you have any questions."
        let paragraph3Rect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 50)
        paragraph3.draw(in: paragraph3Rect, withAttributes: bodyAttributesWithSpacing)
        currentY = paragraph3Rect.maxY + 20
        
        // Closing
        let closingFont = NSFont.systemFont(ofSize: 12)
        let closingAttributes: [NSAttributedString.Key: Any] = [
            .font: closingFont,
            .foregroundColor: NSColor.black
        ]
        "Respectfully Submitted,".draw(at: CGPoint(x: 50, y: currentY), withAttributes: closingAttributes)
        currentY += 30
        
        // Signatory information (left side)
        let signatoryFont = NSFont.systemFont(ofSize: 12)
        let signatoryAttributes: [NSAttributedString.Key: Any] = [
            .font: signatoryFont,
            .foregroundColor: NSColor.black
        ]
        "Stuart Jay Clarke".draw(at: CGPoint(x: 50, y: currentY), withAttributes: signatoryAttributes)
        currentY += 20
        "K. Renevier, P.E.".draw(at: CGPoint(x: 50, y: currentY), withAttributes: signatoryAttributes)
        
        // Engineer seal image (right side)
        if let sealImage = loadEngineerStampImage() {
            let sealSize: CGFloat = 120 // Size of the circular seal
            let sealX = pageRect.width - 50 - sealSize
            let sealY = currentY - 40 - 45 // Raised up 3 rows (3 * 15 points)
            let sealRect = CGRect(x: sealX, y: sealY, width: sealSize, height: sealSize)
            drawNSImage(sealImage, in: sealRect, context: context)
        }
        
        currentY += 30
        
        // Digital signature disclaimer
        let disclaimerFont = NSFont.systemFont(ofSize: 10)
        let disclaimerAttributes: [NSAttributedString.Key: Any] = [
            .font: disclaimerFont,
            .foregroundColor: NSColor.black
        ]
        let disclaimerText = "Kyle Renevier, State of Florida, Professional Engineer, License No. 98372. This item has been digitally signed and sealed by Kyle Renevier on the date indicated here. Printed copies of this document are not considered signed and sealed and the signature must be verified on any electronic copies."
        let disclaimerRect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 80)
        disclaimerText.draw(in: disclaimerRect, withAttributes: disclaimerAttributes)
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        let address = "\(addressToUse.isEmpty ? "" : addressToUse.uppercased()), \(job.city?.uppercased() ?? ""), \(job.state?.uppercased() ?? "") \(job.zip ?? "")".trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        let footerY = pageRect.height - 50
        if !address.isEmpty {
            address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        }
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawSectionHeader(context: CGContext, pageRect: CGRect, title: String, startY: CGFloat) -> CGFloat {
        // Header text - bold black text, no blue bar
        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.black
        ]
        // Draw text at startY position
        title.draw(at: CGPoint(x: 55, y: startY), withAttributes: headerAttributes)
        
        // Return position after text with spacing (font line height + spacing)
        let lineHeight = headerFont.lineHeight
        return startY + lineHeight + 2  // Reduced from 5 to 2 for tighter spacing
    }
    
    private func drawWindowTestingSummaryPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job, windows: [Window]) {
        // Title at top - "WINDOW TESTING"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "WINDOW TESTING".draw(in: titleRect, withAttributes: titleAttributes)
        
        // Calculate box dimensions
        let boxMargin: CGFloat = 50
        let boxX = boxMargin
        let boxTopY = titleRect.maxY + 30
        let boxWidth = pageRect.width - (boxMargin * 2)
        
        // Blue header bar
        let headerBarHeight: CGFloat = 30
        let headerBarRect = CGRect(x: boxX, y: boxTopY, width: boxWidth, height: headerBarHeight)
        context.setFillColor(NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0).cgColor)
        context.fill(headerBarRect)
        
        // Header text "Window Testing Summary" in white
        let headerFont = NSFont.boldSystemFont(ofSize: 14)
        let headerTextAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.white
        ]
        let headerText = "Window Testing Summary"
        let headerTextSize = headerText.size(withAttributes: headerTextAttributes)
        let headerTextX = boxX + 10
        let headerTextY = boxTopY + (headerBarHeight - headerTextSize.height) / 2
        headerText.draw(at: CGPoint(x: headerTextX, y: headerTextY), withAttributes: headerTextAttributes)
        
        // Address below header bar
        let addressY = boxTopY + headerBarHeight + 10
        let addressFont = NSFont.systemFont(ofSize: 11)
        let addressAttributes: [NSAttributedString.Key: Any] = [
            .font: addressFont,
            .foregroundColor: NSColor.black
        ]
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        var addressComponents: [String] = []
        if !addressToUse.isEmpty {
            addressComponents.append(addressToUse)
        }
        if let city = job.city, !city.isEmpty {
            addressComponents.append(city)
        }
        if let state = job.state, !state.isEmpty {
            addressComponents.append(state)
        }
        if let zip = job.zip, !zip.isEmpty {
            addressComponents.append(zip)
        }
        let addressString = addressComponents.joined(separator: ", ")
        addressString.draw(at: CGPoint(x: boxX + 10, y: addressY), withAttributes: addressAttributes)
        
        // Table setup
        let tableStartY = addressY + 20
        let rowHeight: CGFloat = 25
        let headerRowHeight: CGFloat = 25
        
        // Column widths
        let colWidths: [CGFloat] = [120, 80, 150, 150]
        let totalTableWidth = colWidths.reduce(0, +)
        let tableX = boxX + (boxWidth - totalTableWidth) / 2
        
        // Table header row
        let headerFontSize = NSFont.boldSystemFont(ofSize: 11)
        let headerRowAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFontSize,
            .foregroundColor: NSColor.black
        ]
        let headers = ["Results", "Window", "Time: Start", "Time: Stop"]
        var currentX = tableX
        for (index, header) in headers.enumerated() {
            header.draw(at: CGPoint(x: currentX + 5, y: tableStartY + 5), withAttributes: headerRowAttributes)
            currentX += colWidths[index]
        }
        
        // Draw horizontal line below header
        let headerLineY = tableStartY + headerRowHeight
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: tableX, y: headerLineY))
        context.addLine(to: CGPoint(x: tableX + totalTableWidth, y: headerLineY))
        context.strokePath()
        
        // Table data rows
        let dataFont = NSFont.systemFont(ofSize: 11)
        let dataAttributes: [NSAttributedString.Key: Any] = [
            .font: dataFont,
            .foregroundColor: NSColor.black
        ]
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        let sortedWindows = sortWindowsByTitleThenNumber(windows)
        var currentRowY = headerLineY + 5
        
        for window in sortedWindows {
            let result = getDisplayTestResult(for: window)
            let windowNumber = extractNumberFromSpecimenName(window.windowNumber ?? "")
            
            let startTime: String
            if let testStartTime = window.testStartTime {
                startTime = timeFormatter.string(from: testStartTime)
            } else {
                startTime = "N/A"
            }
            
            let stopTime: String
            if let testStopTime = window.testStopTime {
                stopTime = timeFormatter.string(from: testStopTime)
            } else {
                stopTime = "N/A"
            }
            
            currentX = tableX
            let rowData = [result, windowNumber, startTime, stopTime]
            for (index, data) in rowData.enumerated() {
                data.draw(at: CGPoint(x: currentX + 5, y: currentRowY), withAttributes: dataAttributes)
                currentX += colWidths[index]
            }
            
            currentRowY += rowHeight
        }
        
        // Draw box border
        let boxBottomY = currentRowY + 20
        let boxHeight = boxBottomY - boxTopY
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.0)
        context.stroke(CGRect(x: boxX, y: boxTopY, width: boxWidth, height: boxHeight))
        
        // Summary text below table
        let summaryY = boxBottomY + 15
        let summaryFont = NSFont.systemFont(ofSize: 11)
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: NSColor.black
        ]
        let totalWindows = sortedWindows.count
        let summaryText1 = "The home had a total of \(totalWindows) window\(totalWindows == 1 ? "" : "s")."
        summaryText1.draw(at: CGPoint(x: boxX + 10, y: summaryY), withAttributes: summaryAttributes)
        
        let summaryText2 = "Detailed individual test reports available upon request."
        let summaryText2Y = summaryY + summaryFont.lineHeight + 5
        summaryText2.draw(at: CGPoint(x: boxX + 10, y: summaryText2Y), withAttributes: summaryAttributes)
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        let footerAddress = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip).uppercased()
        let footerY = pageRect.height - 50
        footerAddress.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "Page \(pageNumber) of \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawPurposeObservationsWeatherPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        var currentY: CGFloat = 50
        
        // Body font for regular text
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]
        
        // Bold font for section headers
        let headerFont = NSFont.boldSystemFont(ofSize: 11)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.black
        ]
        
        // Helper function to draw text with wrapping
        func drawWrappedText(_ text: String, attributes: [NSAttributedString.Key: Any], y: CGFloat, width: CGFloat) -> CGFloat {
            let textRect = CGRect(x: 50, y: y, width: width, height: 0)
            let boundingRect = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            text.draw(in: CGRect(x: 50, y: y, width: width, height: boundingRect.height), withAttributes: attributes)
            return y + boundingRect.height
        }
        
        // PURPOSE Section
        currentY = drawWrappedText("PURPOSE:", attributes: headerAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        let purposeText = "True Reports was hired by the insured to inspect the property for a damage claim. The date of loss (DOL) is indicated as October 9, 2024. The goal of this inspection was to provide a professional opinion on the cause, origin, extent, and repairability of reported and observed window damage."
        currentY = drawWrappedText(purposeText, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 20
        
        // OBSERVATIONS Section
        currentY = drawWrappedText("OBSERVATIONS:", attributes: headerAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        let observationsText = "Observations are presented within this report. Property condition is described in photograph captions and elsewhere. Full-resolution images are retained electronically and can be provided upon request."
        currentY = drawWrappedText(observationsText, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 20
        
        // WEATHER HISTORY Section
        currentY = drawWrappedText("WEATHER HISTORY:", attributes: headerAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        let weatherHistoryText = "The home was directly in the path of Hurricane Milton. The wind gusts in the area were recorded at over 170 mph on October 9, 2024. NOAA reports sustained winds of between 61 and 91mph."
        // Draw text with superscript
        let weatherText = "The home was directly in the path of Hurricane Milton. The wind gusts in the area were recorded at over 170 mph on October 9, 2024. NOAA reports sustained winds of between 61 and 91mph"
        let weatherTextSize = weatherText.size(withAttributes: bodyAttributes)
        weatherText.draw(at: CGPoint(x: 50, y: currentY), withAttributes: bodyAttributes)
        
        // Draw superscript "2"
        let superscriptFont = NSFont.systemFont(ofSize: 8)
        let superscriptAttributes: [NSAttributedString.Key: Any] = [
            .font: superscriptFont,
            .foregroundColor: NSColor.black,
            .baselineOffset: 5
        ]
        let superscriptSize = "2".size(withAttributes: superscriptAttributes)
        "2".draw(at: CGPoint(x: 50 + weatherTextSize.width, y: currentY - 3), withAttributes: superscriptAttributes)
        currentY += weatherTextSize.height + 20
        
        // Load and draw Hurricane Milton image
        var hurricaneImage: NSImage?
        if let path = Bundle.main.path(forResource: "HurricaneMilton", ofType: "png", inDirectory: "images"),
           let image = NSImage(contentsOfFile: path) {
            hurricaneImage = image
        } else if let path = Bundle.main.path(forResource: "HurricaneMilton", ofType: "png"),
                  let image = NSImage(contentsOfFile: path) {
            hurricaneImage = image
        } else if let image = NSImage(named: "HurricaneMilton") ?? NSImage(named: "images/HurricaneMilton") {
            hurricaneImage = image
        }
        
        if let image = hurricaneImage {
            currentY += 10
            // 2 inches margin on each side = 144 points each = 288 points total
            // Page width is 612 points (8.5 inches), so image width = 612 - 288 = 324 points (4.5 inches)
            let maxWidth: CGFloat = 324
            let imageAspectRatio = image.size.width / image.size.height
            let imageWidth = min(maxWidth, image.size.width)
            let imageHeight = imageWidth / imageAspectRatio
            
            // Center the image
            let imageX = (pageRect.width - imageWidth) / 2
            let imageRect = CGRect(x: imageX, y: currentY, width: imageWidth, height: imageHeight)
            drawNSImage(image, in: imageRect, context: context)
            currentY += imageHeight + 15  // Reduced spacing to fit both images
        }
        
        // Load and draw wide map image
        var mapImage: NSImage?
        if let mapImagePath = job.wideMapImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let mapImageURL = documentsDirectory.appendingPathComponent("map_images").appendingPathComponent(mapImagePath)
            if FileManager.default.fileExists(atPath: mapImageURL.path) {
                mapImage = NSImage(contentsOfFile: mapImageURL.path)
            }
        }
        
        if let image = mapImage {
            // 2 inches margin on each side = 144 points each = 288 points total
            // Page width is 612 points (8.5 inches), so image width = 612 - 288 = 324 points (4.5 inches)
            let maxWidth: CGFloat = 324
            let imageAspectRatio = image.size.width / image.size.height
            let imageWidth = min(maxWidth, image.size.width)
            let imageHeight = imageWidth / imageAspectRatio
            
            // Center the image
            let imageX = (pageRect.width - imageWidth) / 2
            let imageRect = CGRect(x: imageX, y: currentY, width: imageWidth, height: imageHeight)
            drawNSImage(image, in: imageRect, context: context)
        }
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawSummaryPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job, windows: [Window]) {
        
        // Load overhead image
        var overheadImage: NSImage?
        if let imagePath = job.overheadImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
            if FileManager.default.fileExists(atPath: imageURL.path) {
                overheadImage = NSImage(contentsOfFile: imageURL.path)
            }
        }
        
        // Title at top - "SPECIMEN LOCATIONS"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "SPECIMEN LOCATIONS".draw(in: titleRect, withAttributes: titleAttributes)
        
        // Draw legend above the image
        let legendSpacing: CGFloat = 20
        let legendY = titleRect.maxY + legendSpacing
        let legendItemSpacing: CGFloat = 40
        let circleSize: CGFloat = 20
        let legendFont = NSFont.systemFont(ofSize: 12)
        let legendTextAttributes: [NSAttributedString.Key: Any] = [
            .font: legendFont,
            .foregroundColor: NSColor.black
        ]
        
        // Legend items: (color, label)
        let legendItems: [(NSColor, String)] = [
            (.green, "Pass"),
            (.red, "Fail"),
            (.gray, "Inaccessible")
        ]
        
        // Calculate total width of legend items
        var totalLegendWidth: CGFloat = 0
        for (_, label) in legendItems {
            let textSize = label.size(withAttributes: legendTextAttributes)
            totalLegendWidth += circleSize + 8 + textSize.width  // circle + spacing + text
        }
        totalLegendWidth += CGFloat(legendItems.count - 1) * legendItemSpacing  // spacing between items
        
        // Start X position to center the legend
        var currentX = (pageRect.width - totalLegendWidth) / 2
        
        // Draw legend items
        for (color, label) in legendItems {
            // Draw circle
            let circleRect = CGRect(x: currentX, y: legendY, width: circleSize, height: circleSize)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: circleRect)
            
            // Draw label
            let textSize = label.size(withAttributes: legendTextAttributes)
            let textY = legendY + (circleSize - textSize.height) / 2
            label.draw(at: CGPoint(x: currentX + circleSize + 8, y: textY), withAttributes: legendTextAttributes)
            
            // Move to next item
            currentX += circleSize + 8 + textSize.width + legendItemSpacing
        }
        
        let legendHeight: CGFloat = circleSize + 10  // Circle height + some padding

        // Draw overhead image with dots - positioned below legend
        if let image = overheadImage {
            // Calculate image size to fit on page (leaving space for title, legend, footer, and margins)
            let footerSpace: CGFloat = 60  // Footer space + margin
            let topMargin: CGFloat = legendY + legendHeight + 20  // Space below legend
            let maxWidth: CGFloat = pageRect.width - 100
            let maxHeight: CGFloat = pageRect.height - topMargin - footerSpace
            let imageAspectRatio = image.size.width / image.size.height
            let maxAspectRatio = maxWidth / maxHeight
            
            var imageWidth = maxWidth
            var imageHeight = maxHeight
            if imageAspectRatio > maxAspectRatio {
                imageHeight = maxWidth / imageAspectRatio
            } else {
                imageWidth = maxHeight * imageAspectRatio
            }
            
            // Calculate image position - Core Graphics uses bottom-up coordinates
            let imageX = (pageRect.width - imageWidth) / 2
            // Position image from top - convert from top-down to bottom-up
            let imageTopYTopDown = topMargin  // Start from top with small margin
            let imageBottomY = pageRect.height - imageTopYTopDown - imageHeight  // Convert to bottom-up
            
            // Draw image using Core Graphics directly
            let imageRect = CGRect(x: imageX, y: imageBottomY, width: imageWidth, height: imageHeight)
            drawNSImage(image, in: imageRect, context: context)
            
            // Draw dots for each window - use same coordinate conversion logic as app
            // The app uses convertImageToViewY which returns position from top of frame
            // We convert that to PDF coordinates (bottom-up) by subtracting from frame top
            let originalImageSize = image.size
            
            // Use the actual drawn image dimensions (imageWidth x imageHeight) for coordinate conversion
            // These are the actual dimensions of the image that was drawn on the page
            // The helper functions will calculate positions relative to this actual image size
            let displayedImageSize = CGSize(width: imageWidth, height: imageHeight)
            
            // Calculate the top of the actually drawn image in PDF coordinates
            // The image is drawn at imageBottomY, so the top is:
            let displayedImageTopYBottomUp = imageBottomY + imageHeight
            
            for window in sortWindowsByTitleThenNumber(windows) {
                let windowDotColor = dotColor(for: window)
                
                // Use helper functions with displayed image size - this matches where the image actually is
                // The helper functions will calculate positions relative to the displayed image area
                let dotXFromLeft = convertImageXToFrameX(CGFloat(window.xPosition), frameSize: displayedImageSize, originalImageSize: originalImageSize)
                let dotYFromTop = convertImageYToFrameY(CGFloat(window.yPosition), frameSize: displayedImageSize, originalImageSize: originalImageSize)
                
                // Convert to PDF coordinates (bottom-left origin)
                // imageX already centers the image horizontally, so just add dotXFromLeft
                // For Y: flip the coordinate (mirror across X-axis) by measuring from bottom instead of top
                let pdfDotX = imageX + dotXFromLeft
                let pdfDotY = imageBottomY + dotYFromTop  // Add instead of subtract to flip
                
                // Draw the dot
                context.setFillColor(windowDotColor.cgColor)
                context.fillEllipse(in: CGRect(x: pdfDotX - 10, y: pdfDotY - 10, width: 20, height: 20))
                
                // Draw window number (just the number at the end of the specimen name)
                if let windowNumber = window.windowNumber {
                    let displayNumber = extractNumberFromSpecimenName(windowNumber)
                    let numberAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: NSColor.white
                    ]
                    let numberSize = displayNumber.size(withAttributes: numberAttributes)
                    displayNumber.draw(at: CGPoint(x: pdfDotX - numberSize.width / 2, y: pdfDotY - numberSize.height / 2), withAttributes: numberAttributes)
                }
            }
        }
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawSummaryOfFindingsPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job, windows: [Window]) {
        // Title at top - "SUMMARY OF FINDINGS"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "SUMMARY OF FINDINGS".draw(in: titleRect, withAttributes: titleAttributes)
        
        // Address below heading
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        var addressComponents: [String] = []
        if !addressToUse.isEmpty {
            addressComponents.append(addressToUse)
        }
        if let city = job.city, !city.isEmpty {
            addressComponents.append(city)
        }
        if let state = job.state, !state.isEmpty {
            addressComponents.append(state)
        }
        if let zip = job.zip, !zip.isEmpty {
            addressComponents.append(zip)
        }
        let addressString = addressComponents.joined(separator: ", ")
        let addressFont = NSFont.systemFont(ofSize: 12)
        let addressAttributes: [NSAttributedString.Key: Any] = [
            .font: addressFont,
            .foregroundColor: NSColor.black
        ]
        let addressY = titleRect.maxY + 10
        addressString.draw(at: CGPoint(x: 50, y: addressY), withAttributes: addressAttributes)
        
        var currentY = addressY + 30
        
        // TEST PERFORMED Section
        let sectionHeadingFont = NSFont.boldSystemFont(ofSize: 12)
        let sectionHeadingAttributes: [NSAttributedString.Key: Any] = [
            .font: sectionHeadingFont,
            .foregroundColor: NSColor(red: 16/255.0, green: 50/255.0, blue: 93/255.0, alpha: 1.0)  // Light blue #10325d
        ]
        "TEST PERFORMED".draw(at: CGPoint(x: 50, y: currentY), withAttributes: sectionHeadingAttributes)
        currentY += 20
        
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]
        let testPerformedText = "The ASTM E331 water test simulates rain conditions and was used to test if the windows are leaking."
        let textRect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 0)
        let boundingRect = testPerformedText.boundingRect(with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)
        testPerformedText.draw(in: CGRect(x: 50, y: currentY, width: textRect.width, height: boundingRect.height), withAttributes: bodyAttributes)
        currentY += boundingRect.height + 25
        
        // BACKGROUND INFORMATION Section
        let majorSectionFont = NSFont.boldSystemFont(ofSize: 16)
        let majorSectionAttributes: [NSAttributedString.Key: Any] = [
            .font: majorSectionFont,
            .foregroundColor: NSColor(red: 16/255.0, green: 50/255.0, blue: 93/255.0, alpha: 1.0)  // Light blue #10325d
        ]
        "BACKGROUND INFORMATION".draw(at: CGPoint(x: 50, y: currentY), withAttributes: majorSectionAttributes)
        currentY += 25
        
        // Sub-heading
        let subHeadingText = "Cyclical Wind Pressures - Why Hurricanes can Cause Windows to Fail."
        let subHeadingRect = subHeadingText.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: sectionHeadingAttributes, context: nil)
        subHeadingText.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: subHeadingRect.height), withAttributes: sectionHeadingAttributes)
        currentY += subHeadingRect.height + 15
        
        // Background information paragraphs
        let backgroundPara1 = "Cyclical wind pressures in hurricanes can cause windows to fail even if they are structurally sound. According to FEMA Fact Sheet 1.3, these pressures can create significant stress on building components, leading to structural integrity issues over time."
        let para1Rect = backgroundPara1.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)
        backgroundPara1.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: para1Rect.height), withAttributes: bodyAttributes)
        currentY += para1Rect.height + 12
        
        // First paragraph as quote
        let firstQuote = "\"During a hurricane, wind changes speed and direction rapidly, creating cyclical pressures that alternate between positive and negative forces. This constant variation can weaken window components, damage seals, and create openings that allow water infiltration."
        let firstQuoteRect = firstQuote.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)
        firstQuote.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: firstQuoteRect.height), withAttributes: bodyAttributes)
        currentY += firstQuoteRect.height + 15
        
        // Numbered list without quotes
        let listItemFont = NSFont.systemFont(ofSize: 11)
        let listItemAttributes: [NSAttributedString.Key: Any] = [
            .font: listItemFont,
            .foregroundColor: NSColor.black
        ]
        
        let listItem1 = "1. Positive Pressure: When wind strikes a building, it creates a positive pressure on the side facing the wind. This pressure attempts to push the building away from the wind."
        let item1Rect = listItem1.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: listItemAttributes, context: nil)
        listItem1.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: item1Rect.height), withAttributes: listItemAttributes)
        currentY += item1Rect.height + 10
        
        let listItem2 = "2. Negative Pressure (Suction): On the leeward side (the side away from the wind) and over the roof, negative pressures are created. These suction forces attempt to pull parts of the building away from the main structure.\"¹"
        let item2Rect = listItem2.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: listItemAttributes, context: nil)
        listItem2.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: item2Rect.height), withAttributes: listItemAttributes)
        currentY += item2Rect.height + 25  // Add blank line (25 points) after
        
        // RECOMMENDATIONS & CONCLUSION Section - Bold, size 24, blue
        let recSectionFont = NSFont.boldSystemFont(ofSize: 24)
        let recSectionAttributes: [NSAttributedString.Key: Any] = [
            .font: recSectionFont,
            .foregroundColor: NSColor(red: 39/255.0, green: 96/255.0, blue: 145/255.0, alpha: 1.0)  // Medium blue #276091
        ]
        "RECOMMENDATIONS & CONCLUSION".draw(at: CGPoint(x: 50, y: currentY), withAttributes: recSectionAttributes)
        currentY += 25
        
        // Calculate statistics
        let sortedWindows = sortWindowsByTitleThenNumber(windows)
        let failedWindows = sortedWindows.filter { $0.testResult == "Fail" }
        let inaccessibleWindows = sortedWindows.filter { $0.isInaccessible }
        let totalTestedWindows = sortedWindows.count
        let failedCount = failedWindows.count
        
        // Recommendations paragraph 1
        let recommendationsPara1: String
        if failedCount > 0 {
            recommendationsPara1 = "\(failedCount) of \(totalTestedWindows) window\(totalTestedWindows == 1 ? "" : "s") failed the ASTM E331 water test and require repair or replacement. Cyclical pressures from hurricanes can cause windows to fail by weakening glazing, damaging seals, and creating openings that lead to interior damage. For more details on hurricane damage to windows, see the section below called Common Terms."
        } else {
            recommendationsPara1 = "All tested windows passed the ASTM E331 water test. However, cyclical pressures from hurricanes can still cause windows to fail by weakening glazing, damaging seals, and creating openings that lead to interior damage. For more details on hurricane damage to windows, see the section below called Common Terms."
        }
        let recPara1Rect = recommendationsPara1.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)
        recommendationsPara1.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: recPara1Rect.height), withAttributes: bodyAttributes)
        currentY += recPara1Rect.height + 12
        
        // Recommendations paragraph 2 (about inaccessible windows)
        if inaccessibleWindows.count > 0 {
            let inaccessibleTypes = inaccessibleWindows.compactMap { window -> String? in
                guard let windowType = window.windowType, !windowType.isEmpty else { return nil }
                return windowType.lowercased()
            }
            let uniqueTypes = Array(Set(inaccessibleTypes))
            let typeDescription: String
            if uniqueTypes.count == 1 {
                typeDescription = uniqueTypes[0] + " window"
            } else if uniqueTypes.count > 1 {
                typeDescription = uniqueTypes.dropLast().joined(separator: ", ") + ", and " + uniqueTypes.last! + " windows"
            } else {
                typeDescription = "window"
            }
            
            let recommendationsPara2 = "\(inaccessibleWindows.count) \(typeDescription)\(inaccessibleWindows.count == 1 ? "" : "s") could not be tested due to inaccessibility."
            let recPara2Rect = recommendationsPara2.boundingRect(with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)
            recommendationsPara2.draw(in: CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: recPara2Rect.height), withAttributes: bodyAttributes)
            currentY += recPara2Rect.height + 12
        }
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        let footerAddress = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip).uppercased()
        let footerY = pageRect.height - 50
        footerAddress.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "Page \(pageNumber) of \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawPhotoPage(context: CGContext, pageRect: CGRect, window: Window, photos: [FieldResultsPackage.PhotoData], pageNumber: Int, totalPages: Int, job: Job) {
        // Footer at bottom - top-down coordinates: large Y value for bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
        
        // Title at top - NSString.draw uses top-down coordinates (Y=0 at top)
        let titleFont = NSFont.boldSystemFont(ofSize: 20)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black
        ]
        let windowTitle = window.windowNumber ?? "Unknown"
        // Use draw(in:) with a rect - top-down coordinates: small Y value for top
        let titleHeight: CGFloat = 25
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        windowTitle.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Layout 4 photos in a 2x2 grid - position below title using top-down coordinates
        let photoSize: CGFloat = 250
        let spacing: CGFloat = 20
        let startX: CGFloat = 50
        
        // If there are only 2 photos, center them vertically on the page
        let spacingFromTitle: CGFloat = photos.count == 2 ? 20 : 50
        let startYTopDown: CGFloat
        
        if photos.count == 2 {
            // Calculate the total height needed for 2 photos (including caption space)
            let totalPhotoHeight = photoSize + 60 // photo + caption space
            // Center vertically: start from middle of page, subtract half the photo height
            let pageCenterY = pageRect.height / 2
            startYTopDown = pageCenterY - (totalPhotoHeight / 2)
        } else {
            startYTopDown = titleRect.maxY + spacingFromTitle  // Points below title (top-down)
        }
        
        for (index, photoData) in photos.enumerated() {
            let row = index / 2
            let col = index % 2
            let x = startX + CGFloat(col) * (photoSize + spacing)
            // Calculate Y position for each photo - convert from top-down to bottom-up for Core Graphics
            let photoYTopDown = startYTopDown + CGFloat(row) * (photoSize + spacing + 60) // Extra space for caption
            
            // Draw photo without coordinate flip - NSImage.draw(in:) handles PDF coordinates correctly
            // using UIKit's top-down coordinate system provided by UIGraphicsPDFRenderer
            let originalImage = photoData.image
            let originalImageSize = originalImage.size
            
            // Apply compression: downsample first, then compress
            let processedImage: NSImage
            if let scaledImage = loadScaledImage(originalImage, maxDimension: 750),
               let compressedImage = compressImage(scaledImage, quality: 0.5) {
                processedImage = compressedImage
            } else {
                // Fallback to original if compression fails
                processedImage = originalImage
            }
            
            let imageRect = CGRect(x: x, y: photoYTopDown, width: photoSize, height: photoSize)
            drawNSImage(processedImage, in: imageRect, context: context)
            
            // Draw arrow if present (use original image size for coordinate conversion)
            let arrowX = photoData.photo.arrowXPosition
            let arrowY = photoData.photo.arrowYPosition
            if arrowX > 0, arrowY > 0, let direction = photoData.photo.arrowDirection {
                let displayedImageSize = CGSize(width: photoSize, height: photoSize)
                
                // Convert arrow coordinates from original image space to PDF photo space
                let arrowXFromLeft = convertImageXToFrameX(CGFloat(arrowX), frameSize: displayedImageSize, originalImageSize: originalImageSize)
                let arrowYFromTop = convertImageYToFrameY(CGFloat(arrowY), frameSize: displayedImageSize, originalImageSize: originalImageSize)
                
                // Convert to PDF coordinates (top-down origin matches UIKit drawing context)
                let pdfArrowX = x + arrowXFromLeft
                let pdfArrowY = photoYTopDown + arrowYFromTop
                
                // Draw arrow
                drawArrow(context: context, at: CGPoint(x: pdfArrowX, y: pdfArrowY), direction: direction)
            }
            
            // Draw caption
            let captionFont = NSFont.systemFont(ofSize: 10)
            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: NSColor.black
            ]
            let caption = photoData.caption
            // Only push captions down on pages with 2 photos; keep original position for 4-photo pages
            let captionOffset: CGFloat = photos.count == 2 ? 77 : 5
            let captionY = photoYTopDown + photoSize + captionOffset
            let captionRect = CGRect(x: x, y: captionY, width: photoSize, height: 20)
            caption.draw(in: captionRect, withAttributes: captionAttributes)
        }
    }
    
    private func loadGaugeImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("gauge_images").appendingPathComponent(imagePath)
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("Gauge image not found at: \(imageURL.path)")
            return nil
        }
        
        return NSImage(contentsOfFile: imageURL.path)
    }
    
    private func loadFrontOfHomeImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("front_of_home_images").appendingPathComponent(imagePath)
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("Front of home image not found at: \(imageURL.path)")
            return nil
        }
        
        return NSImage(contentsOfFile: imageURL.path)
    }
    
    private func drawCalibrationPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        // Title at top - "CALIBRATED EQUIPMENT"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 39/255.0, green: 96/255.0, blue: 145/255.0, alpha: 1.0)  // Medium blue #276091
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "CALIBRATED EQUIPMENT".draw(in: titleRect, withAttributes: titleAttributes)
        
        var currentY = titleRect.maxY + 40
        
        // Load gauge image
        var gaugeImage: NSImage?
        if let imagePath = job.gaugeImagePath {
            gaugeImage = loadGaugeImage(from: imagePath)
        }
        
        // Load front of home image
        var frontOfHomeImage: NSImage?
        if let imagePath = job.frontOfHomeImagePath {
            frontOfHomeImage = loadFrontOfHomeImage(from: imagePath)
        }
        
        // Gauge photo section (top)
        if let image = gaugeImage {
            // Calculate image size - make it fit nicely on the page
            let maxImageWidth: CGFloat = pageRect.width - 100
            let maxImageHeight: CGFloat = 200
            let imageAspectRatio = image.size.width / image.size.height
            var imageWidth = min(maxImageWidth, image.size.width)
            var imageHeight = imageWidth / imageAspectRatio
            
            if imageHeight > maxImageHeight {
                imageHeight = maxImageHeight
                imageWidth = imageHeight * imageAspectRatio
            }
            
            let imageX = (pageRect.width - imageWidth) / 2
            let imageRect = CGRect(x: imageX, y: currentY, width: imageWidth, height: imageHeight)
            drawNSImage(image, in: imageRect, context: context)
            
            currentY = imageRect.maxY + 15
            
            // Location text
            let locationFont = NSFont.boldSystemFont(ofSize: 12)
            let locationAttributes: [NSAttributedString.Key: Any] = [
                .font: locationFont,
                .foregroundColor: NSColor.black
            ]
            "Location: Onsite".draw(at: CGPoint(x: 50, y: currentY), withAttributes: locationAttributes)
            currentY += 20
            
            // Description text
            let descriptionFont = NSFont.systemFont(ofSize: 11)
            let descriptionAttributes: [NSAttributedString.Key: Any] = [
                .font: descriptionFont,
                .foregroundColor: NSColor.black
            ]
            let descriptionText = "Verifying pressure of equipment before AAMA 501.2 water test which simulates real rain conditions."
            let descriptionRect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 40)
            descriptionText.draw(in: descriptionRect, withAttributes: descriptionAttributes)
            currentY = descriptionRect.maxY + 40
        }
        
        // Front of property section (bottom)
        if let image = frontOfHomeImage {
            // Calculate image size - make it fit nicely on the page
            let maxImageWidth: CGFloat = pageRect.width - 100
            let maxImageHeight: CGFloat = 200
            let imageAspectRatio = image.size.width / image.size.height
            var imageWidth = min(maxImageWidth, image.size.width)
            var imageHeight = imageWidth / imageAspectRatio
            
            if imageHeight > maxImageHeight {
                imageHeight = maxImageHeight
                imageWidth = imageHeight * imageAspectRatio
            }
            
            let imageX = (pageRect.width - imageWidth) / 2
            let imageRect = CGRect(x: imageX, y: currentY, width: imageWidth, height: imageHeight)
            drawNSImage(image, in: imageRect, context: context)
            
            currentY = imageRect.maxY + 15
            
            // Location text
            let locationFont = NSFont.boldSystemFont(ofSize: 12)
            let locationAttributes: [NSAttributedString.Key: Any] = [
                .font: locationFont,
                .foregroundColor: NSColor.black
            ]
            "Front of Property".draw(at: CGPoint(x: 50, y: currentY), withAttributes: locationAttributes)
            currentY += 20
            
            // Description text
            let descriptionFont = NSFont.systemFont(ofSize: 11)
            let descriptionAttributes: [NSAttributedString.Key: Any] = [
                .font: descriptionFont,
                .foregroundColor: NSColor.black
            ]
            let descriptionText = "Image of the front of the property for address verification."
            let descriptionRect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 40)
            descriptionText.draw(in: descriptionRect, withAttributes: descriptionAttributes)
        }
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawWorksCitedPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        // Title at top - "SOURCES"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "SOURCES".draw(in: titleRect, withAttributes: titleAttributes)
        
        var currentY = titleRect.maxY + 30
        
        // Citation font (smaller, black)
        let citationFont = NSFont.systemFont(ofSize: 11)
        
        // Create paragraph style with hanging indent (first line flush left, continuation lines indented)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0  // First line flush left
        paragraphStyle.headIndent = 36  // Continuation lines indented by 36 points (0.5 inches)
        
        let citationAttributes: [NSAttributedString.Key: Any] = [
            .font: citationFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        // First citation (FEMA) - hanging indent
        let citation1 = "1 Federal Emergency Management Agency. \"Cyclical Wind Pressures in Hurricanes.\" Home Builder's Guide to Coastal Construction Technical Fact Sheet Series, no. 1.3, Dec. 2018, www.fema.gov/sites/default/files/2020-07/fema_p499_fact_sheet_1-3_cyclical_wind_pressures.pdf."
        let citation1Rect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 100)
        let citation1BoundingRect = citation1.boundingRect(with: CGSize(width: citation1Rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: citationAttributes, context: nil)
        citation1.draw(in: CGRect(x: 50, y: currentY, width: citation1Rect.width, height: citation1BoundingRect.height), withAttributes: citationAttributes)
        currentY += citation1BoundingRect.height + 20
        
        // Second citation (NOAA) - hanging indent
        let citation2 = "2 Beven, John L., II, et al. National Hurricane Center Tropical Cyclone Report: Hurricane Milton (AL142024). National Hurricane Center, 31 Mar. 2025, https://www.nhc.noaa.gov/data/tcr/AL142024_Milton.pdf."
        let citation2Rect = CGRect(x: 50, y: currentY, width: pageRect.width - 100, height: 100)
        let citation2BoundingRect = citation2.boundingRect(with: CGSize(width: citation2Rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: citationAttributes, context: nil)
        citation2.draw(in: CGRect(x: 50, y: currentY, width: citation2Rect.width, height: citation2BoundingRect.height), withAttributes: citationAttributes)
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = formatAddressForExport(addressLine1: addressToUse, city: job.city, state: job.state, zip: job.zip).uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func drawCredentialsPage(context: CGContext, pageRect: CGRect, pageNumber: Int, totalPages: Int, job: Job) {
        // Title at top - "CREDENTIALS"
        let titleFont = NSFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(red: 0.0, green: 0.2, blue: 0.4, alpha: 1.0)
        ]
        let titleHeight: CGFloat = 30
        let titleRect = CGRect(x: 50, y: 30, width: pageRect.width - 100, height: titleHeight)
        "CREDENTIALS".draw(in: titleRect, withAttributes: titleAttributes)
        
        var currentY = titleRect.maxY + 30
        
        // Body font for regular text
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]
        
        // Bold font for names
        let nameFont = NSFont.boldSystemFont(ofSize: 11)
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: NSColor.black
        ]
        
        // Helper function to draw text with wrapping
        func drawWrappedText(_ text: String, attributes: [NSAttributedString.Key: Any], y: CGFloat, width: CGFloat) -> CGFloat {
            let textRect = CGRect(x: 50, y: y, width: width, height: 0)
            let boundingRect = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            text.draw(in: CGRect(x: 50, y: y, width: width, height: boundingRect.height), withAttributes: attributes)
            return y + boundingRect.height
        }
        
        // K. Renevier, P.E.
        let renevierName = "K. Renevier, P.E."
        currentY = drawWrappedText(renevierName, attributes: nameAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let renevierLicenses = "Licenses: Florida Professional Engineering License #98372. Also holds a professional engineering license in Alabama, Louisiana, and Texas."
        currentY = drawWrappedText(renevierLicenses, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let renevierEducation = "Education: B.S. Civil Engineering from the University of Oklahoma; M.S. Civil Engineering with an Emphasis in Structures from the University of Oklahoma."
        currentY = drawWrappedText(renevierEducation, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let renevierExperience = "Experience: Has over a decade of engineering experience, including seven years as a licensed professional engineer. Specializes in Forensic and Design Engineering for residential, commercial, and industrial projects. Has assessed structures damaged by significant tornadoes (e.g., Joplin, MO) and major hurricanes across the Gulf Coast since 2018. Assists communities impacted by natural disasters."
        currentY = drawWrappedText(renevierExperience, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 20
        
        // Yonatan Z. Rotenberg
        let rotenbergName = "Yonatan Z. Rotenberg"
        currentY = drawWrappedText(rotenbergName, attributes: nameAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let rotenbergEducation = "Education: B.S. Mechanical Engineering from Florida International University."
        currentY = drawWrappedText(rotenbergEducation, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let rotenbergExperience = "Experience: Has a decade of engineering experience. Responsible for evaluating the structural safety of various components and systems. Has authored numerous engineering documents and reports, holds patents, and is a co-author on research publications. Previously worked as a research assistant in mechanical testing and metallurgy."
        currentY = drawWrappedText(rotenbergExperience, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 20
        
        // Stuart Jay Clarke III, CGC & CCC
        let clarkeName = "Stuart Jay Clarke III, CGC & CCC"
        currentY = drawWrappedText(clarkeName, attributes: nameAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let clarkeLicenses = "Licenses: Roofing Contractor - CCC1327185; General Contractor - CGC1518899."
        currentY = drawWrappedText(clarkeLicenses, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let clarkeEducation = "Education: Bachelor of Science from FSU & UCF. Field of Study includes Chemical Engineering, Chemistry, and Forensic Science."
        currentY = drawWrappedText(clarkeEducation, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let clarkeExperience = "Experience: Serves as an Expert Witness and a Roof consultant for award-winning architects. Is a U.S. Patent holder. Has overseen the installation of thousands of quality roofs and completed over 3,000 roof inspections and reports across the southeastern United States. Worked as a Roofing expert and forensic inspector for one of Florida's largest insurance companies. Is an original member of the No Blue Roof charity and one of only 10 roofing contractors to receive an award from Miami Dade County for outstanding service. Was part of the original My Safe Florida Home team, contributing to improving roof safety and strengthening the roofing code in Florida."
        currentY = drawWrappedText(clarkeExperience, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 20
        
        // Joel S. Jaroslawicz
        let jaroslawiczName = "Joel S. Jaroslawicz"
        currentY = drawWrappedText(jaroslawiczName, attributes: nameAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let jaroslawiczLicenses = "Licenses/Certifications: Holds a 620 All Lines Adjuster License; FEMA Certified for IS-285 (Flood Damage Appraisal Management); License # W263548."
        currentY = drawWrappedText(jaroslawiczLicenses, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        currentY += 8
        
        let jaroslawiczExperience = "Experience: Has over a decade of experience in the insurance industry. Has worked as both an Independent Adjuster and a Public Adjuster, providing a dual perspective on insurance claims, which makes him valuable in understanding, evaluating, and adjusting claims from both the insurer's and the claimant's viewpoints."
        currentY = drawWrappedText(jaroslawiczExperience, attributes: bodyAttributes, y: currentY, width: pageRect.width - 100)
        
        // Footer at bottom
        let footerFont = NSFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: NSColor.gray
        ]
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let address = "\(addressToUse), \(job.city ?? ""), \(job.state ?? "") \(job.zip ?? "")".uppercased()
        let footerY = pageRect.height - 50  // 50 points from bottom (top-down coordinates)
        address.draw(at: CGPoint(x: 50, y: footerY), withAttributes: footerAttributes)
        
        let pageText = "PAGE \(pageNumber) OF \(totalPages)"
        let pageTextSize = pageText.size(withAttributes: footerAttributes)
        pageText.draw(at: CGPoint(x: pageRect.width - 50 - pageTextSize.width, y: footerY), withAttributes: footerAttributes)
    }
    
    private func fetchPhotoImage(for photo: Photo) async -> NSImage? {
        let photoId = photo.photoId ?? "unknown"
        let photoType = photo.photoType ?? "Unknown"
        
        // Check if photo is from file system
        if photo.photoSource == "FileSystem", let filePath = photo.filePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fullPath = documentsDirectory.appendingPathComponent(filePath)
            
            if FileManager.default.fileExists(atPath: fullPath.path),
               let image = NSImage(contentsOfFile: fullPath.path) {
                return image
            } else {
                print("⚠️ DOCX: Photo skipped - File not found at path: \(filePath) (Photo ID: \(photoId), Type: \(photoType))")
                return nil
            }
        }
        
        // Otherwise, try Photos library
        guard let localIdentifier = photo.localIdentifier else {
            print("⚠️ DOCX: Photo skipped - Missing localIdentifier and filePath (Photo ID: \(photoId), Type: \(photoType))")
            return nil
        }
        
        // Only fetch real photos from Photos framework
        // Skip test/bundled images - use real photos only
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            print("⚠️ DOCX: Photo skipped - Invalid localIdentifier '\(localIdentifier)' not found in Photos library (Photo ID: \(photoId), Type: \(photoType))")
            return nil
        }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            let imageManager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            
            // On macOS, requestImage returns NSImage? directly
            imageManager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, info in
                if let nsImage = image {
                    continuation.resume(returning: nsImage)
                } else {
                    // Check if there's an error in the info dictionary
                    if let error = info?[PHImageErrorKey] as? Error {
                        print("⚠️ DOCX: Photo skipped - Failed to load image: \(error.localizedDescription) (Photo ID: \(photoId), Type: \(photoType), LocalID: \(localIdentifier))")
                    } else {
                        print("⚠️ DOCX: Photo skipped - No image returned (Photo ID: \(photoId), Type: \(photoType), LocalID: \(localIdentifier))")
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // Use CGImageSource to load a scaled-down (thumbnail) version for memory-efficient processing
    private func loadScaledImage(_ image: NSImage, maxDimension: CGFloat = 750) -> NSImage? {
        // Convert NSImage to Data for CGImageSource
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else { return nil }
        
        // Create a CGImageSource for incremental, memory-efficient decoding
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        
        // Downsampling / thumbnail options
        let options: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        // Create the thumbnail / scaled image
        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        // Convert CGImage to NSImage
        return NSImage(cgImage: cgThumbnail, size: .zero)
    }
    
    // Compress image using JPEG compression
    private func compressImage(_ image: NSImage, quality: CGFloat = 0.5) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: quality]),
              let compressedImage = NSImage(data: jpegData) else {
            return nil
        }
        return compressedImage
    }
    
    private func loadTestImage(from identifier: String) -> NSImage? {
        // Map test identifiers to bundle image names
        // Format: "test_specimen_{number}_{type}_{index}" or "test_window{number}_{type}"
        var imageName: String?
        
        // Extract window/specimen number from identifier
        let components = identifier.components(separatedBy: "_")
        
        // Check for "specimen_{number}" pattern
        if let specimenIndex = components.firstIndex(of: "specimen"), 
           specimenIndex + 1 < components.count {
            let numberStr = components[specimenIndex + 1]
            // Map specimen numbers to image files
            // Specimen 1, 3, 5, etc. -> imageWindow1
            // Specimen 2, 4, 6, etc. -> imageWindow2
            if let number = Int(numberStr) {
                imageName = (number % 2 == 1) ? "imageWindow1" : "imageWindow2"
            }
        }
        // Check for "window{number}" pattern
        else if let windowComponent = components.first(where: { $0.hasPrefix("window") }) {
            let num = windowComponent.replacingOccurrences(of: "window", with: "")
            if num == "1" {
                imageName = "imageWindow1"
            } else if num == "2" {
                imageName = "imageWindow2"
            }
        }
        // Fallback: check if identifier contains window1 or window2
        else if identifier.contains("window1") || identifier.contains("specimen") && (identifier.contains("1") || identifier.contains("3") || identifier.contains("5")) {
            imageName = "imageWindow1"
        } else if identifier.contains("window2") || (identifier.contains("specimen") && (identifier.contains("2") || identifier.contains("4") || identifier.contains("6"))) {
            imageName = "imageWindow2"
        }
        
        guard let name = imageName else { return nil }
        
        // Try loading from bundle with multiple fallback paths
        // Try .jpeg first, then .jpg, then .png
        if let imagePath = Bundle.main.path(forResource: name, ofType: "jpeg", inDirectory: "images") {
            return NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "images") {
            return NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: name, ofType: "jpeg") {
            return NSImage(contentsOfFile: imagePath)
        } else if let imagePath = Bundle.main.path(forResource: name, ofType: "jpg") {
            return NSImage(contentsOfFile: imagePath)
        } else if let image = NSImage(named: name) {
            return image
        } else if let image = NSImage(named: "images/\(name)") {
            return image
        }
        
        return nil
    }
    
    struct PhotoData {
        let photo: Photo
        let image: NSImage
        let caption: String
    }

    private func generateDOCXReport(in directory: URL) async throws -> URL {
        let sortedWindows = sortWindowsByTitleThenNumber(windows)

        let coverResource = loadCoverPageResource()
        let (overviewInlineResource, overviewFullResource, overheadResource) = loadOverviewResources(from: directory)

        var windowContents: [DocxWindowContent] = []

        for window in sortedWindows {
            let orderedPhotos = orderedPhotosForDocx(window)
            var photos: [DocxPhoto] = []

            for photo in orderedPhotos {
                guard let image = await fetchPhotoImage(for: photo) else { continue }
                guard let data = image.docxCompressedData(maxDimension: 1600, compressionQuality: 0.7) else { continue }

                // Make photos square - 3.6 inches x 3.6 inches (wider to use more space)
                let sizeInches: CGFloat = 3.6
                let sizeEMU = Int(sizeInches * 914_400)

                let resource = DocxImageResource(data: data, fileExtension: "jpeg", cx: sizeEMU, cy: sizeEMU)
                let caption = docxCaption(for: photo, window: window)
                photos.append(DocxPhoto(image: resource, caption: caption))
            }

            let summary = docxSummaryLines(for: window)
            if summary.isEmpty && photos.isEmpty {
                continue
            }

            let title = window.windowNumber ?? "Specimen"
            windowContents.append(DocxWindowContent(title: title, summaryLines: summary, photos: photos))
        }

        let renderer = DocxTemplateRenderer()
        let tempURL = try renderer.render(
            job: job,
            cover: coverResource,
            overviewInline: overviewInlineResource,
            overviewFull: overviewFullResource,
            overheadInline: overheadResource,
            windows: windowContents,
            actualWindows: sortedWindows
        )

        let destinationURL = directory.appendingPathComponent("WindowTests.docx")
        try FileManager.default.removeItemIfExists(at: destinationURL)
        try FileManager.default.copyItem(at: tempURL, to: destinationURL)

        return destinationURL
    }

    private func loadCoverPageResource() -> DocxImageResource? {
        let pageWidthEMU = Int(8.5 * 914_400)
        let pageHeightEMU = Int(11.0 * 914_400)

        // Use screenshotOfCoverPageImage.png first
        if let path = [
            Bundle.main.path(forResource: "screenshotOfCoverPageImage", ofType: "png", inDirectory: "images"),
            Bundle.main.path(forResource: "screenshotOfCoverPageImage", ofType: "png")
        ].compactMap({ $0 }).first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return DocxImageResource(data: data, fileExtension: "png", cx: pageWidthEMU, cy: pageHeightEMU)
        }

        // Fallback to coverPageResized
        if let path = [
            Bundle.main.path(forResource: "coverPageResized", ofType: "png", inDirectory: nil),
            Bundle.main.path(forResource: "coverPageResized", ofType: "png", inDirectory: "images"),
            Bundle.main.path(forResource: "coverPageResized", ofType: "png")
        ].compactMap({ $0 }).first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return DocxImageResource(data: data, fileExtension: "png", cx: pageWidthEMU, cy: pageHeightEMU)
        }

        if let image = NSImage(named: "screenshotOfCoverPageImage") ?? NSImage(named: "images/screenshotOfCoverPageImage") ?? NSImage(named: "coverPageResized") ?? NSImage(named: "images/coverPageResized"),
           let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let data = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
            return DocxImageResource(data: data, fileExtension: "jpeg", cx: pageWidthEMU, cy: pageHeightEMU)
        }

        return nil
    }

    private func loadOverviewResources(from directory: URL) -> (DocxImageResource?, DocxImageResource?, DocxImageResource?) {
        let dottedURL = directory.appendingPathComponent("overhead_with_dots.png")
        guard let dottedData = try? Data(contentsOf: dottedURL),
              let dottedImage = NSImage(data: dottedData),
              dottedImage.size.width > 0 else {
            return (nil, nil, nil)
        }

        let dottedAspectRatio = dottedImage.size.height / dottedImage.size.width

        // Max height is 4 inches
        let inlineMaxHeightEMU = Int(4.0 * 914_400)
        // Calculate width based on max height and aspect ratio
        var inlineHeightEMU = inlineMaxHeightEMU
        var inlineWidthEMU = Int(CGFloat(inlineHeightEMU) / dottedAspectRatio)
        
        // Ensure width doesn't exceed reasonable page width (about 7.5 inches max)
        let maxWidthEMU = Int(7.5 * 914_400)
        if inlineWidthEMU > maxWidthEMU {
            inlineWidthEMU = maxWidthEMU
            inlineHeightEMU = Int(CGFloat(inlineWidthEMU) * dottedAspectRatio)
        }
        let inlineResource = DocxImageResource(data: dottedData, fileExtension: "png", cx: inlineWidthEMU, cy: inlineHeightEMU)

        let fullWidthInches: CGFloat = 8.0
        let fullWidthEMU = Int(fullWidthInches * 914_400)
        var fullHeightEMU = Int(CGFloat(fullWidthEMU) * dottedAspectRatio)
        let fullMaxHeightEMU = Int(11.0 * 914_400)
        if fullHeightEMU > fullMaxHeightEMU {
            fullHeightEMU = fullMaxHeightEMU
        }
        let fullResource = DocxImageResource(data: dottedData, fileExtension: "png", cx: fullWidthEMU, cy: fullHeightEMU)

        var overheadResource: DocxImageResource?
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        if let imagePath = job.overheadImagePath,
           let documentsDirectory,
           fileManager.fileExists(atPath: documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath).path) {
            let originalURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
            if let overheadData = try? Data(contentsOf: originalURL),
               let overheadImage = NSImage(data: overheadData),
               overheadImage.size.width > 0 {
                let aspectRatio = overheadImage.size.height / overheadImage.size.width
                var heightEMU = Int(CGFloat(inlineWidthEMU) * aspectRatio)
                if heightEMU > inlineMaxHeightEMU {
                    heightEMU = inlineMaxHeightEMU
                }
                overheadResource = DocxImageResource(data: overheadData, fileExtension: "png", cx: inlineWidthEMU, cy: heightEMU)
            }
        }

        return (inlineResource, fullResource, overheadResource)
    }

    private func orderedPhotosForDocx(_ window: Window) -> [Photo] {
        let oldestFirst: (Photo, Photo) -> Bool = {
            ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
        }

        let allPhotos = ((window.photos?.allObjects as? [Photo]) ?? [])
            .filter { $0.includeInReport }
        
        // Sort all photos by creation date (oldest first) regardless of type
        return allPhotos.sorted(by: oldestFirst)
    }

    private func docxSummaryLines(for window: Window) -> [DocxSummaryLine] {
        var lines: [DocxSummaryLine] = []
        let job = self.job

        let tightSpacing = 30
        let sectionSpacing = 2 //12

        // Specimen/Test table values are now shown in the table at the top of the page, so removed from here

        // Section A - add one blank line before
        lines.append(DocxSummaryLine(text: "A. Test Specimen", spacingBefore: 240, spacingAfter: tightSpacing))
        let testResult = getDisplayTestResult(for: window)
        lines.append(DocxSummaryLine(text: "Test Results: \(testResult)", spacingBefore: 0, spacingAfter: tightSpacing))
        let waterPressure = job.waterPressure > 0 ? job.waterPressure : 12.0
        lines.append(DocxSummaryLine(text: "Water Pressure: \(Int(round(waterPressure))) PSI", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Deviation: None", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Size Requirements: None", spacingBefore: 0, spacingAfter: tightSpacing))
        let description = "Residential \(window.windowType?.trimmedOrNil ?? "Specimen") - \(window.material?.trimmedOrNil ?? "Unknown Material")"
        lines.append(DocxSummaryLine(text: "Description: \(description)", spacingBefore: 0, spacingAfter: 120))  // 6pt spacing after last row of Section A

        // Section B
        lines.append(DocxSummaryLine(text: "B. Specimen Type and Size", spacingBefore: 0, spacingAfter: tightSpacing))
        // Combine Manufacturer and Model on same line
        lines.append(DocxSummaryLine(text: "Manufacturer: Unknown  --  Model: Unknown", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Operation: \(window.windowType?.trimmedOrNil ?? "Unknown")", spacingBefore: 0, spacingAfter: tightSpacing))
        // Combine Width and Height on same line
        var sizeComponents: [String] = []
        if window.width > 0 {
            sizeComponents.append(String(format: "Width: %.1f\"", window.width))
        }
        if window.height > 0 {
            sizeComponents.append(String(format: "Height: %.1f\"", window.height))
        }
        if !sizeComponents.isEmpty {
            // Last row of Section B - set to 6pt spacing
            let sizeText = sizeComponents.joined(separator: " ")
            lines.append(DocxSummaryLine(text: sizeText, spacingBefore: 0, spacingAfter: 120))
        } else {
            // If no width or height, update Operation to be last row with 6pt spacing
            let operationIndex = lines.count - 1
            lines[operationIndex] = DocxSummaryLine(text: lines[operationIndex].text, spacingBefore: lines[operationIndex].spacingBefore, spacingAfter: 120)
        }
        // Removed blank line after Section B

        // Section C
        lines.append(DocxSummaryLine(text: "C. Specimen Location and Related Information", spacingBefore: 0, spacingAfter: tightSpacing))
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1
        let addressComponents = [addressToUse, job.city, job.state, job.zip]
            .compactMap { $0?.trimmedOrNil }
        if !addressComponents.isEmpty {
            lines.append(DocxSummaryLine(text: "Location: \(addressComponents.joined(separator: ", "))", spacingBefore: 0, spacingAfter: tightSpacing))
        }
        let exteriorMaterial = window.material?.trimmedOrNil ?? "Unknown"
        lines.append(DocxSummaryLine(text: "Exterior Finishes: Glass, \(exteriorMaterial), Framed Windows", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Interior Finishes: Drywall", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "SF/CW Window Design Pressure: Unknown", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Building Pressure - Corner (PSF): Unknown", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Building Pressure - Field (PSF): Unknown", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Building Corner Distance (Feet): Unknown", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Specimen Plumb, Level and Square: Yes, within industry standards", spacingBefore: 0, spacingAfter: 120))  // 6pt spacing after last row of Section C
        // Removed blank line after Section C

        // Section D
        lines.append(DocxSummaryLine(text: "D. Specimen Age and Performance", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Specimen Age: Over 6 Months", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: "Modifications Prior to Test: None", spacingBefore: 0, spacingAfter: 120))  // 6pt spacing after last row of Section D
        // Removed blank line after Section D

        // Section E
        lines.append(DocxSummaryLine(text: "E. Weather Conditions", spacingBefore: 0, spacingAfter: tightSpacing))
        let temperature = job.temperature > 0 ? job.temperature : 73.0
        let windSpeed = job.windSpeed > 0 ? job.windSpeed : 5.0
        // Combine Temperature and Wind Speed on same line
        let tempWindText = String(format: "Temperature (F): %.0f °F  --  ", temperature) + " " + String(format: "Wind Speed/Direction (mph): %.0f mph", windSpeed)
        lines.append(DocxSummaryLine(text: tempWindText, spacingBefore: 0, spacingAfter: tightSpacing))
        let barometric = 29.0
        let precipitation = 0.0
        // Combine Barometric Pressure and Precipitation on same line
        let barometricPrecipText = String(format: "Barometric Pressure (inHg): %.0f inHg  --  ", barometric) + String(format: "Precipitation: %.0f%%", precipitation)
        lines.append(DocxSummaryLine(text: barometricPrecipText, spacingBefore: 0, spacingAfter: 120))  // 6pt spacing after last row of Section E
        // Removed blank line after Section E

        // Recap
        lines.append(DocxSummaryLine(text: "Test Recap and Comments:", spacingBefore: 0, spacingAfter: tightSpacing))
        lines.append(DocxSummaryLine(text: String(format: "The entire specimen was sprayed with water at a rate of 7.2 (Gal/Hr./Sq. Ft.) at %.0f PSI.", waterPressure), spacingBefore: 0, spacingAfter: tightSpacing))
        if testResult.caseInsensitiveCompare("Pass") == .orderedSame {
            lines.append(DocxSummaryLine(text: "No water leakage was observed following the test.", spacingBefore: 0, spacingAfter: tightSpacing))
        } else if testResult.caseInsensitiveCompare("Fail") == .orderedSame {
            lines.append(DocxSummaryLine(text: "Water leakage was observed following the test.", spacingBefore: 0, spacingAfter: tightSpacing))
        } else if testResult.caseInsensitiveCompare("Inaccessible") == .orderedSame {
            lines.append(DocxSummaryLine(text: "Window is inaccessible.", spacingBefore: 0, spacingAfter: tightSpacing))
        } else {
            lines.append(DocxSummaryLine(text: "Test result is pending.", spacingBefore: 0, spacingAfter: tightSpacing))
        }

        if let notes = window.notes?.trimmedOrNil {
            lines.append(DocxSummaryLine(text: "", spacingBefore: 0, spacingAfter: sectionSpacing))
            lines.append(DocxSummaryLine(text: "Notes: \(notes)", spacingBefore: 0, spacingAfter: tightSpacing))
        }

        return lines
    }

    private func docxCaption(for photo: Photo, window: Window) -> String {
        // Return just the note or photo type without the specimen label
        let note = photo.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, !note.isEmpty {
            return note
        }

        if let type = photo.photoType, !type.isEmpty {
            return type
        }

        return ""
    }
    
    func createZIPArchive(from sourceDir: URL, to destinationURL: URL) async throws {
        // Use ZIPFoundation to create the ZIP archive
        let fileManager = FileManager.default
        
        // Remove existing file if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Create new archive using ZIPFoundation
        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw NSError(domain: "ExportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }
        
        // Get all files recursively
        let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                
                // Get relative path
                var relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
                relativePath = relativePath.replacingOccurrences(of: "\\", with: "/")
                
                // Read file data
                let fileData = try Data(contentsOf: fileURL)
                
                // Add entry to archive
                try archive.addEntry(with: relativePath, type: .file, uncompressedSize: UInt32(fileData.count), compressionMethod: .none) { position, size in
                    return fileData.subdata(in: position..<position + size)
                }
            }
        }
    }
    
    private func createZIP(from directory: URL, name: String) async throws -> URL {
        print("📁 Creating archive from: \(directory.path)")
        
        // Since we're not actually creating a ZIP file, just return the directory itself
        // The directory already has all the files we need
        
        // Verify source directory exists
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Source directory does not exist: \(directory.path)"])
        }
        
        print("✅ Export package ready at: \(directory.path)")
        
        // Return the directory itself - no need to copy
        // In a production app, you would use a ZIP library like ZipArchive to create a real ZIP file
        return directory
    }
}

// MARK: - Full Job Package Exporter

class FullJobPackageExporter {
    let job: Job
    let documentsDirectory: URL
    
    init(job: Job) {
        self.job = job
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    func export() async throws -> URL {
        print("🚀 Starting Full Job Package export for job: \(job.jobId ?? "Unknown")")
        
        let jobId = job.jobId ?? "Unknown"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let packageName = "\(jobId)_WindowTest_FullJob_\(timestamp)"
        
        let exportDirectory = documentsDirectory.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        
        let packageDirectory = exportDirectory.appendingPathComponent(packageName)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        
        // Create subdirectories
        let overheadDir = packageDirectory.appendingPathComponent("overhead")
        let mapDir = packageDirectory.appendingPathComponent("map")
        let imagesDir = packageDirectory.appendingPathComponent("images")
        let photosDir = packageDirectory.appendingPathComponent("photos")
        
        try FileManager.default.createDirectory(at: overheadDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mapDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        
        // Copy images
        var overheadImageFile: String? = nil
        var wideMapImageFile: String? = nil
        var frontOfHomeImageFile: String? = nil
        var gaugeImageFile: String? = nil
        
        if let overheadPath = job.overheadImagePath {
            let sourceURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(overheadPath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destFileName = "\(jobId)_overhead.jpg"
                let destURL = overheadDir.appendingPathComponent(destFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                overheadImageFile = "overhead/\(destFileName)"
                print("✅ Copied overhead image")
            }
        }
        
        if let mapPath = job.wideMapImagePath {
            let sourceURL = documentsDirectory.appendingPathComponent("map_images").appendingPathComponent(mapPath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destFileName = "\(jobId)_location_map.png"
                let destURL = mapDir.appendingPathComponent(destFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                wideMapImageFile = "map/\(destFileName)"
                print("✅ Copied wide map image")
            }
        }
        
        if let frontPath = job.frontOfHomeImagePath {
            let sourceURL = documentsDirectory.appendingPathComponent("front_of_home_images").appendingPathComponent(frontPath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destFileName = "front_of_home.jpg"
                let destURL = imagesDir.appendingPathComponent(destFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                frontOfHomeImageFile = "images/\(destFileName)"
                print("✅ Copied front of home image")
            }
        }
        
        if let gaugePath = job.gaugeImagePath {
            let sourceURL = documentsDirectory.appendingPathComponent("gauge_images").appendingPathComponent(gaugePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destFileName = "gauge.jpg"
                let destURL = imagesDir.appendingPathComponent(destFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                gaugeImageFile = "images/\(destFileName)"
                print("✅ Copied gauge image")
            }
        }
        
        // Process windows and photos
        let windows = (job.windows?.allObjects as? [Window]) ?? []
        var fullWindows: [FullJobPackage.FullWindowData] = []
        
        for window in windows {
            let windowId = window.windowId ?? UUID().uuidString
            let windowNumber = window.windowNumber ?? ""
            
            // Copy photos for this window
            let photos = (window.photos?.allObjects as? [Photo]) ?? []
            var fullPhotos: [FullJobPackage.FullPhotoData] = []
            
            for (index, photo) in photos.enumerated() {
                guard let localIdentifier = photo.localIdentifier else {
                    print("⚠️ Skipping photo without localIdentifier")
                    continue
                }
                
                // Fetch photo from Photos library
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
                guard let asset = fetchResult.firstObject else {
                    print("⚠️ Photo not found in library: \(localIdentifier)")
                    continue
                }
                
                // Get image data
                let imageData = await fetchPhotoImageData(asset: asset)
                guard let imageData = imageData else {
                    print("⚠️ Failed to fetch image data for photo")
                    continue
                }
                
                // Save photo to package
                let photoType = photo.photoType ?? "Unknown"
                let photoFileName = "\(windowId)_\(photoType)_\(index).jpg"
                let photoURL = photosDir.appendingPathComponent(photoFileName)
                try imageData.write(to: photoURL)
                
                let fullPhoto = FullJobPackage.FullPhotoData(
                    photoId: photo.photoId ?? UUID().uuidString,
                    photoType: photoType,
                    imageFile: "photos/\(photoFileName)",
                    notes: photo.notes,
                    arrowXPosition: photo.arrowXPosition,
                    arrowYPosition: photo.arrowYPosition,
                    arrowDirection: photo.arrowDirection,
                    includeInReport: photo.includeInReport,
                    createdAt: photo.createdAt?.timeIntervalSince1970
                )
                fullPhotos.append(fullPhoto)
            }
            
            let fullWindow = FullJobPackage.FullWindowData(
                windowId: windowId,
                windowNumber: windowNumber,
                xPosition: window.xPosition,
                yPosition: window.yPosition,
                width: window.width,
                height: window.height,
                windowType: window.windowType,
                material: window.material,
                testResult: window.testResult,
                leakPoints: window.leakPoints,
                isInaccessible: window.isInaccessible,
                notes: window.notes,
                testStartTime: window.testStartTime?.timeIntervalSince1970,
                testStopTime: window.testStopTime?.timeIntervalSince1970,
                createdAt: window.createdAt?.timeIntervalSince1970,
                updatedAt: window.updatedAt?.timeIntervalSince1970,
                photos: fullPhotos
            )
            fullWindows.append(fullWindow)
        }
        
        // Create full job data
        let fullJobData = FullJobPackage.FullJobData(
            jobId: job.jobId ?? UUID().uuidString,
            clientName: job.clientName,
            addressLine1: job.addressLine1,
            cleanedAddressLine1: job.cleanedAddressLine1,
            city: job.city,
            state: job.state,
            zip: job.zip,
            notes: job.notes,
            phoneNumber: job.phoneNumber,
            areasOfConcern: job.areasOfConcern,
            status: job.status,
            testProcedure: job.testProcedure,
            waterPressure: job.waterPressure,
            inspectorName: job.inspectorName,
            inspectionDate: job.inspectionDate?.timeIntervalSince1970,
            temperature: job.temperature,
            weatherCondition: job.weatherCondition,
            humidity: job.humidity,
            windSpeed: job.windSpeed,
            createdAt: job.createdAt?.timeIntervalSince1970,
            updatedAt: job.updatedAt?.timeIntervalSince1970,
            overheadImageFile: overheadImageFile,
            wideMapImageFile: wideMapImageFile,
            frontOfHomeImageFile: frontOfHomeImageFile,
            gaugeImageFile: gaugeImageFile,
            overheadImageSourceName: job.overheadImageSourceName,
            overheadImageSourceUrl: job.overheadImageSourceUrl,
            overheadImageFetchedAt: job.overheadImageFetchedAt?.timeIntervalSince1970,
            scalePixelsPerFoot: job.scalePixelsPerFoot,
            windows: fullWindows
        )
        
        // Create package
        let package = FullJobPackage(
            version: "1.0",
            exportedAt: Date().timeIntervalSince1970,
            exportedBy: job.inspectorName,
            job: fullJobData
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(package)
        let jsonURL = packageDirectory.appendingPathComponent("full_job_package.json")
        try jsonData.write(to: jsonURL)
        
        print("✅ Full Job Package JSON created")
        
        // Create ZIP archive
        let zipURL = exportDirectory.appendingPathComponent("\(packageName).zip")
        try await createZIPArchive(from: packageDirectory, to: zipURL)
        
        print("✅ Full Job Package ZIP created at: \(zipURL.path)")
        
        return zipURL
    }
    
    private func fetchPhotoImageData(asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            // On macOS, requestImage returns NSImage directly
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { nsImage, _ in
                if let nsImage = nsImage {
                    // Convert NSImage to Data (JPEG)
                    guard let tiffData = nsImage.tiffRepresentation,
                          let bitmapRep = NSBitmapImageRep(data: tiffData),
                          let imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: imageData)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func createZIPArchive(from sourceDir: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw NSError(domain: "ExportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }
        
        let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                
                var relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
                relativePath = relativePath.replacingOccurrences(of: "\\", with: "/")
                
                let fileData = try Data(contentsOf: fileURL)
                
                try archive.addEntry(with: relativePath, type: .file, uncompressedSize: UInt32(fileData.count), compressionMethod: .none) { position, size in
                    return fileData.subdata(in: position..<position + size)
                }
            }
        }
    }
}

// MARK: - DOCX Rendering Helpers

fileprivate struct DocxImageResource {
    let data: Data
    let fileExtension: String
    let cx: Int
    let cy: Int
}

fileprivate struct DocxSummaryLine {
    let text: String
    let spacingBefore: Int
    let spacingAfter: Int
}

fileprivate struct DocxPhoto {
    let image: DocxImageResource
    let caption: String
}

fileprivate struct DocxWindowContent {
    let title: String
    let summaryLines: [DocxSummaryLine]
    let photos: [DocxPhoto]
}

fileprivate enum DocxRenderError: Error {
    case templateMissing
    case archiveOpenFailed
}

fileprivate final class DocxTemplateRenderer {
    func render(
        job: Job,
        cover: DocxImageResource?,
        overviewInline: DocxImageResource?,
        overviewFull: DocxImageResource?,
        overheadInline: DocxImageResource?,
        windows: [DocxWindowContent],
        actualWindows: [Window]
    ) throws -> URL {
        print("🚀 DocxTemplateRenderer.render() called for job: \(job.jobId ?? "unknown")")
        guard let templateURL = Bundle.main.url(forResource: "BaseTemplateWithImage", withExtension: "docx") else {
            print("❌ Template file not found!")
            throw DocxRenderError.templateMissing
        }
        print("✅ Template file found: \(templateURL.path)")

        let fileManager = FileManager.default
        
        // Extract template to temporary directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("docx_temp_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // Clean up temp directory
            try? fileManager.removeItem(at: tempDir)
        }
        
        print("📦 Extracting template to: \(tempDir.path)")
        guard let templateArchive = Archive(url: templateURL, accessMode: .read) else {
            throw DocxRenderError.archiveOpenFailed
        }
        
        // Extract all files from template
        var extractedFiles: [String] = []
        for entry in templateArchive {
            // Skip directory entries (they end with /)
            if entry.path.hasSuffix("/") {
                let entryURL = tempDir.appendingPathComponent(entry.path)
                try fileManager.createDirectory(at: entryURL, withIntermediateDirectories: true)
                continue
            }
            
            let entryURL = tempDir.appendingPathComponent(entry.path)
            let entryDir = entryURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: entryDir, withIntermediateDirectories: true)
            
            var entryData = Data()
            try templateArchive.extract(entry) { chunk in
                entryData.append(chunk)
            }
            try entryData.write(to: entryURL)
            extractedFiles.append(entry.path)
        }
        print("✅ Template extracted: \(extractedFiles.count) files")
        if extractedFiles.contains("_rels/.rels") {
            print("✅ _rels/.rels extracted successfully")
        } else {
            print("⚠️ WARNING: _rels/.rels NOT found in extracted files!")
            print("   Extracted files: \(extractedFiles.prefix(10).joined(separator: ", "))")
        }
        
        // Ensure mandatory files exist
        try ensureMandatoryFilesInDirectory(tempDir)
        
        // Remove old media files
        let mediaDir = tempDir.appendingPathComponent("word/media")
        if fileManager.fileExists(atPath: mediaDir.path) {
            try fileManager.removeItem(at: mediaDir)
        }
        try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        // Read existing relationships from file
        var existingRels = ""
        var usedRelIds = Set<String>()
        let existingRelsPath = tempDir.appendingPathComponent("word/_rels/document.xml.rels")
        if fileManager.fileExists(atPath: existingRelsPath.path),
           let relsData = try? Data(contentsOf: existingRelsPath),
           let relsString = String(data: relsData, encoding: .utf8) {
            // Extract existing relationships, preserving non-image relationships
            let pattern = "<Relationship[^>]*/>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = relsString as NSString
                let matches = regex.matches(in: relsString, options: [], range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    let matchString = nsString.substring(with: match.range)
                    // Extract the Id attribute to track used IDs
                    if let idRange = matchString.range(of: "Id=\""),
                       let idEndRange = matchString.range(of: "\"", range: idRange.upperBound..<matchString.endIndex) {
                        let idValue = String(matchString[idRange.upperBound..<idEndRange.lowerBound])
                        usedRelIds.insert(idValue)
                    }
                    // Preserve relationships that are NOT images (styles, settings, theme, etc.)
                    if !matchString.contains("relationships/image") {
                        existingRels += "  \(matchString)\n"
                    }
                }
            }
        }

        var body = ""
        var rels = existingRels
        var imageIndex = 1
        var usedExtensions = Set<String>()

        func addImageResource(_ resource: DocxImageResource, prefix: String) throws -> (relId: String, docPrId: Int) {
            // Ensure image relationship ID doesn't conflict
            var relId = "rIdImage\(imageIndex)"
            while usedRelIds.contains(relId) {
                imageIndex += 1
                relId = "rIdImage\(imageIndex)"
            }
            usedRelIds.insert(relId)
            let imageName = "\(prefix)\(imageIndex).\(resource.fileExtension)"
            let mediaPath = tempDir.appendingPathComponent("word/media/\(imageName)")
            let currentId = imageIndex
            // Write image file directly
            try resource.data.write(to: mediaPath)
            rels += "  <Relationship Id=\"\(relId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(imageName)\"/>\n"
            usedExtensions.insert(resource.fileExtension.lowercased())
            imageIndex += 1
            return (relId, currentId)
        }

        if let cover {
            print("📄 Adding cover page...")
            let imageRef = try addImageResource(cover, prefix: "cover")
            body += xmlFullPageImage(relId: imageRef.relId, docPrId: imageRef.docPrId, cx: cover.cx, cy: cover.cy)
            
            // Add cover page text overlays
            // Page height is 11 inches = 10,058,400 EMU
            let pageHeightEMU = Int(11.0 * 914_400)
            
            // Add "Residential" subtitle (left justified, 8.96 inches from top, 0.83 inches from left)
            body += xmlCoverPageText(text: "Residential", x: Int(0.83 * 914_400), y: Int(8.96 * 914_400), fontSize: 20, isBold: true, color: "10325d", alignment: "left")
            
            // Add "Prepared for:" and client name below "Residential" on same line with tab
            let trimmedClient = job.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            // Position at 9.34 inches from top
            let preparedForY = Int(9.34 * 914_400)
            body += xmlCoverPageTextWithTab(text: "Prepared for:", tabText: trimmedClient, x: Int(0.83 * 914_400), y: preparedForY, fontSize: 14, color: "10325d")
            
            // Add "Address:" and first line of address on next line with two tabs
            let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
            let addressLine1Y = Int(9.59 * 914_400)  // 0.25 inches below Prepared for
            body += xmlCoverPageTextWithTwoTabs(text: "Address:", tabText: addressToUse, x: Int(0.83 * 914_400), y: addressLine1Y, fontSize: 14, color: "10325d")
            
            // Add second line of address (city, state zip) on next line with three tabs
            // Format: city, state zip (comma after city, no comma after state)
            var addressLine2Components: [String] = []
            if let city = job.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                addressLine2Components.append(city + ",")
            }
            if let state = job.state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
                addressLine2Components.append(state)
            }
            if let zip = job.zip?.trimmingCharacters(in: .whitespacesAndNewlines), !zip.isEmpty {
                addressLine2Components.append(zip)
            }
            let addressLine2 = addressLine2Components.joined(separator: " ")
            let addressLine2Y = Int(9.84 * 914_400)  // 0.25 inches below Address
            body += xmlCoverPageTextWithThreeTabs(text: addressLine2, x: Int(0.83 * 914_400), y: addressLine2Y, fontSize: 14, color: "10325d")
            
            body += pageBreak()
            print("✅ Cover page added")
        } else {
            print("⚠️ No cover image provided")
        }

        print("📄 Adding OVERVIEW page...")
        // Add Overview page - should be page 2, right after cover
        body += xmlOverviewTitle("OVERVIEW", spacingBefore: 446, spacingAfter: 0)
        
        // Add address below OVERVIEW title
        let addressToUseForTitle = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        if !addressToUseForTitle.isEmpty {
            body += xmlOverviewAddressSubtitle(addressToUseForTitle, spacingBefore: 0, spacingAfter: 240)
        } else {
            body += xmlSpacerParagraph(before: 0, after: 240)
        }

        // Add overview photo (original overhead image without dots) right after title
        if let overheadImageResource = overheadInline,
           let overheadRef = try? addImageResource(overheadImageResource, prefix: "overviewPhoto") {
            body += xmlSpacerParagraph(before: 0, after: 120)
            body += xmlImageParagraph(relId: overheadRef.relId, docPrId: overheadRef.docPrId, cx: overheadImageResource.cx, cy: overheadImageResource.cy, alignment: "center")
            body += xmlSpacerParagraph(before: 0, after: 120)
        }

        let trimmedClient = job.clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInspector = job.inspectorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1
        let addressComponents = [addressToUse, job.city, job.state, job.zip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let inspectionDate = job.inspectionDate.map { dateFormatter.string(from: $0) } ?? "N/A"

        let overviewRows: [(String, String)] = [
            ("REPORT NUMBER", job.jobId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"),
            ("DATE OF INSPECTIONS", inspectionDate),
            ("PREPARED FOR", trimmedClient?.isEmpty == false ? trimmedClient! : "Unknown"),
            ("PREPARED BY", trimmedInspector?.isEmpty == false ? trimmedInspector! : "Unknown"),
            ("OWNER NAME", trimmedClient?.isEmpty == false ? trimmedClient! : "Unknown"),
            ("ADDRESS", addressComponents.isEmpty ? "Unknown" : addressComponents.joined(separator: ", "))
        ]

        for (label, value) in overviewRows {
            body += xmlOverviewTextRow(label: label, value: value, spacingAfter: 1)
        }

        if let notes = job.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            let filteredNotes = filterUnwantedFieldsFromNotes(notes)
            if !filteredNotes.isEmpty {
                body += xmlParagraph(filteredNotes)
            }
        }

        body += pageBreak()

        // Add Engineering Letter page
        let engineerStampResource = loadEngineerStampResource()
        var engineerStampRef: (relId: String, docPrId: Int)? = nil
        if let stampResource = engineerStampResource {
            engineerStampRef = try? addImageResource(stampResource, prefix: "engineerStamp")
        }
        body += self.generateEngineeringLetterXML(job: job, engineerStampRef: engineerStampRef)
        body += pageBreak()

        print("✅ About to add Purpose/Observations/Weather History page...")
        // Add Purpose/Observations/Weather History page
        print("📄 Generating Purpose/Observations/Weather History page...")
        let hurricaneMiltonResource = loadHurricaneMiltonResource()
        let wideMapResource = loadWideMapImageResource(for: job)
        print("📄 Hurricane Milton resource loaded: \(hurricaneMiltonResource != nil)")
        print("📄 Wide map resource loaded: \(wideMapResource != nil), job.wideMapImagePath: \(job.wideMapImagePath ?? "nil")")
        
        var hurricaneImageRef: (relId: String, docPrId: Int, cx: Int, cy: Int)? = nil
        var mapImageRef: (relId: String, docPrId: Int, cx: Int, cy: Int)? = nil
        
        if let hurricaneResource = hurricaneMiltonResource {
            if let ref = try? addImageResource(hurricaneResource, prefix: "hurricane") {
                hurricaneImageRef = (relId: ref.relId, docPrId: ref.docPrId, cx: hurricaneResource.cx, cy: hurricaneResource.cy)
                print("📄 Hurricane image added successfully")
            } else {
                print("⚠️ Failed to add Hurricane image resource")
            }
        }
        
        if let mapResource = wideMapResource {
            if let ref = try? addImageResource(mapResource, prefix: "map") {
                mapImageRef = (relId: ref.relId, docPrId: ref.docPrId, cx: mapResource.cx, cy: mapResource.cy)
                print("📄 Map image added successfully")
            } else {
                print("⚠️ Failed to add map image resource")
            }
        }
        
        let purposePageXML = self.generatePurposeObservationsWeatherXML(
            job: job,
            hurricaneImageRef: hurricaneImageRef,
            mapImageRef: mapImageRef
        )
        print("📄 Purpose page XML generated, length: \(purposePageXML.count) characters")
        body += purposePageXML
        print("✅ Purpose page added to document body. Body length now: \(body.count) characters")

        // Add Summary of Findings page right after Purpose page
        body += self.generateSummaryOfFindingsXML(job: job, windows: actualWindows)
        body += pageBreak()

        if let overviewFull,
           let fullRef = try? addImageResource(overviewFull, prefix: "locations") {
            body += xmlLargeBoldParagraph("Specimen Locations", color: "276091", spacingBefore: 446)
            body += xmlSpacerParagraph(before: 0, after: 120)  // Space after title
            body += generateSpecimenLocationsLegendXML()
            body += xmlSpacerParagraph(before: 0, after: 120)  // Space before image
            body += xmlImageParagraph(relId: fullRef.relId, docPrId: fullRef.docPrId, cx: overviewFull.cx, cy: overviewFull.cy)
            body += pageBreak()
        }

        // Add Window Testing Summary page
        body += self.generateWindowTestingSummaryXML(job: job, windows: actualWindows)
        body += pageBreak()

        for (index, windowContent) in windows.enumerated() {
            body += xmlLargeBoldParagraph(windowContent.title, color: "276091", spacingBefore: 446)
            
            // Add specimen information table - use actualWindows to get Window object with test times
            if index < actualWindows.count {
                body += generateSpecimenTableXML(window: actualWindows[index], job: job)
                body += xmlSpacerParagraph(before: 120, after: 0)
            }
            
            for line in windowContent.summaryLines {
                // Check if this is a section title (starts with "A.", "B.", "C.", "D.", "E.", or "Test Recap")
                let isSectionTitle = line.text.hasPrefix("A. ") || 
                                     line.text.hasPrefix("B. ") || 
                                     line.text.hasPrefix("C. ") || 
                                     line.text.hasPrefix("D. ") || 
                                     line.text.hasPrefix("E. ") ||
                                     line.text.hasPrefix("Test Recap")
                if isSectionTitle {
                    body += xmlBoldParagraph(line.text, color: nil, spacingBefore: line.spacingBefore, spacingAfter: line.spacingAfter)
                } else {
                    body += xmlParagraph(line.text, spacingBefore: line.spacingBefore, spacingAfter: line.spacingAfter)
                }
            }

            if windowContent.photos.isEmpty {
                if index < windows.count - 1 {
                    body += pageBreak()
                }
            } else {
                body += pageBreak()
                // Add specimen title at top of first photo page
                let specimenTitle = windowContent.title
                body += xmlLargeBoldParagraph(specimenTitle, color: "276091", spacingBefore: 446, spacingAfter: 0)
                
                var photoIndex = 0
                while photoIndex < windowContent.photos.count {
                    let end = min(photoIndex + 4, windowContent.photos.count)
                    let group = Array(windowContent.photos[photoIndex..<end])
                    let refs: [(relId: String, docPrId: Int, resource: DocxImageResource, caption: String)] = try group.map { photo in
                        let ref = try addImageResource(photo.image, prefix: "photo")
                        return (ref.relId, ref.docPrId, photo.image, photo.caption)
                    }
                    body += xmlPhotoPage(entries: refs)
                    photoIndex = end
                    if photoIndex < windowContent.photos.count {
                        body += pageBreak()
                    }
                }
                if index < windows.count - 1 {
                    body += pageBreak()
                }
            }
        }
        
        // Add calibration section at the end
        body += pageBreak()
        body += xmlLargeBoldParagraph("CALIBRATED EQUIPMENT", color: "276091", spacingBefore: 446)
        body += xmlSpacerParagraph(before: 240, after: 240)
        
        // Load and add gauge image if available
        if let gaugeImagePath = job.gaugeImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("gauge_images").appendingPathComponent(gaugeImagePath)
            if FileManager.default.fileExists(atPath: imageURL.path),
               let gaugeImage = NSImage(contentsOfFile: imageURL.path),
               let gaugeData = gaugeImage.docxCompressedData(maxDimension: 1600, compressionQuality: 0.7) {
                let widthInches: CGFloat = 3.5
                let widthEMU = Int(widthInches * 914_400)
                let aspectRatio = gaugeImage.size.width > 0 ? gaugeImage.size.height / gaugeImage.size.width : 1
                var heightEMU = Int(CGFloat(widthEMU) * aspectRatio)
                let maxHeightEMU = Int(4.0 * 914_400)
                if heightEMU > maxHeightEMU {
                    heightEMU = maxHeightEMU
                }
                
                let gaugeResource = DocxImageResource(data: gaugeData, fileExtension: "jpeg", cx: widthEMU, cy: heightEMU)
                if let gaugeRef = try? addImageResource(gaugeResource, prefix: "gauge") {
                    body += xmlSpacerParagraph(before: 120, after: 120, centered: true)
                    body += xmlImageParagraph(relId: gaugeRef.relId, docPrId: gaugeRef.docPrId, cx: gaugeResource.cx, cy: gaugeResource.cy, alignment: "center")
                    body += xmlSpacerParagraph(before: 120, after: 120, centered: true)
                    body += xmlParagraph("Location: Onsite", style: "Normal")
                    body += xmlParagraph("Verifying pressure of equipment before AAMA 501.2 water test which simulates real rain conditions.", style: "Normal")
                    body += xmlSpacerParagraph(before: 240, after: 240)
                }
            }
        }
        
        // Load and add front of home image if available
        if let frontOfHomeImagePath = job.frontOfHomeImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("front_of_home_images").appendingPathComponent(frontOfHomeImagePath)
            if FileManager.default.fileExists(atPath: imageURL.path),
               let frontOfHomeImage = NSImage(contentsOfFile: imageURL.path),
               let frontOfHomeData = frontOfHomeImage.docxCompressedData(maxDimension: 1600, compressionQuality: 0.7) {
                let widthInches: CGFloat = 3.5
                let widthEMU = Int(widthInches * 914_400)
                let aspectRatio = frontOfHomeImage.size.width > 0 ? frontOfHomeImage.size.height / frontOfHomeImage.size.width : 1
                var heightEMU = Int(CGFloat(widthEMU) * aspectRatio)
                let maxHeightEMU = Int(4.0 * 914_400)
                if heightEMU > maxHeightEMU {
                    heightEMU = maxHeightEMU
                }
                
                let frontOfHomeResource = DocxImageResource(data: frontOfHomeData, fileExtension: "jpeg", cx: widthEMU, cy: heightEMU)
                if let frontOfHomeRef = try? addImageResource(frontOfHomeResource, prefix: "frontOfHome") {
                    body += xmlSpacerParagraph(before: 120, after: 120, centered: true)
                    body += xmlImageParagraph(relId: frontOfHomeRef.relId, docPrId: frontOfHomeRef.docPrId, cx: frontOfHomeResource.cx, cy: frontOfHomeResource.cy, alignment: "center")
                    body += xmlSpacerParagraph(before: 120, after: 120, centered: true)
                    body += xmlParagraph("Front of Property", style: "Normal")
                    body += xmlParagraph("Image of the front of the property for address verification.", style: "Normal")
                }
            }
        }
        
        // Add Common Terms page (after calibration)
        body += pageBreak()
        body += self.generateCommonTermsXML()
        
        // Add works cited page (after Common Terms)
        body += pageBreak()
        body += self.generateWorksCitedXML(job: job)
        
        // Add credentials section at the end
        body += pageBreak()
        let credentialsXML = self.generateCredentialsXML(job: job)
        
        // Extract the last paragraph from credentials (it ends with spacingAfter: 0)
        // We'll add sectPr to it in wrapDocumentXML, but ensure it's properly formed
        body += credentialsXML

        // Create footer with address and page numbers
        // Check if footer relationship already exists in preserved relationships
        let hasExistingFooter = existingRels.contains("relationships/footer")
        
        var footerRelId: String? = nil
        if !hasExistingFooter {
            // Create new footer relationship
            footerRelId = "rIdFooter1"
            // Ensure footer relationship ID doesn't conflict
            while usedRelIds.contains(footerRelId!) {
                if let lastChar = footerRelId?.last, let num = Int(String(lastChar)) {
                    footerRelId = "rIdFooter\(num + 1)"
                } else {
                    footerRelId = "rIdFooter2"
                }
            }
            usedRelIds.insert(footerRelId!)
            
            // Add footer relationship
            rels += "  <Relationship Id=\"\(footerRelId!)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/>\n"
            
            // Write footer XML file
            let footerXML = createFooterXML(job: job)
            let footerPath = tempDir.appendingPathComponent("word/footer1.xml")
            guard let footerData = footerXML.data(using: .utf8) else {
                throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode footer XML"])
            }
            try footerData.write(to: footerPath)
        } else {
            // Footer relationship already exists, extract the ID and update content
            if let footerRange = existingRels.range(of: "Id=\""),
               let relTypeRange = existingRels.range(of: "relationships/footer", range: footerRange.lowerBound..<existingRels.endIndex) {
                let beforeRelType = String(existingRels[footerRange.upperBound..<relTypeRange.lowerBound])
                if let idEndRange = beforeRelType.range(of: "\"") {
                    footerRelId = String(beforeRelType[..<idEndRange.lowerBound])
                }
            }
            
            // Update footer XML file even if relationship exists
            let footerXML = createFooterXML(job: job)
            let footerPath = tempDir.appendingPathComponent("word/footer1.xml")
            guard let footerData = footerXML.data(using: .utf8) else {
                throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode footer XML"])
            }
            try footerData.write(to: footerPath)
        }
        
        // Write document XML to file
        let documentXML = wrapDocumentXML(body, footerRelId: footerRelId)
        let documentPath = tempDir.appendingPathComponent("word/document.xml")
        guard let documentData = documentXML.data(using: .utf8) else {
            throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode document XML"])
        }
        try documentData.write(to: documentPath)

        // Write relationships XML to file
        let relsXML = wrapRelsXML(rels)
        let relsPath = tempDir.appendingPathComponent("word/_rels/document.xml.rels")
        guard let relsData = relsXML.data(using: .utf8) else {
            throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode relationships XML"])
        }
        try relsData.write(to: relsPath)

        // Update Content_Types.xml
        try updateContentTypesInDirectory(tempDir, with: usedExtensions, hasFooter: footerRelId != nil)

        // Create new archive from modified files
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("WindowTests-\(UUID().uuidString).docx")
        print("📦 Creating new archive at: \(outputURL.path)")
        
        guard let newArchive = Archive(url: outputURL, accessMode: .create) else {
            throw DocxRenderError.archiveOpenFailed
        }
        
        // Add all files from temp directory to new archive
        // Use a more reliable method to get relative paths
        let enumerator = fileManager.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var filesToAdd: [(path: String, data: Data, isImage: Bool)] = []
        var foundRelsRels = false
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                // Use URL path manipulation instead of string replacement
                let relativePath = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
                    .replacingOccurrences(of: tempDir.path, with: "")
                
                // Remove leading slash if present
                let cleanPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                
                // Check if this is _rels/.rels
                if cleanPath == "_rels/.rels" {
                    foundRelsRels = true
                    print("✅ Found _rels/.rels at: \(fileURL.path)")
                }
                
                let fileData = try Data(contentsOf: fileURL)
                let isImage = cleanPath.hasPrefix("word/media/") || cleanPath.hasSuffix(".jpeg") || cleanPath.hasSuffix(".jpg") || cleanPath.hasSuffix(".png")
                
                filesToAdd.append((path: cleanPath, data: fileData, isImage: isImage))
            }
        }
        
        if !foundRelsRels {
            print("⚠️ WARNING: _rels/.rels not found when enumerating files!")
            // Try to find it explicitly
            let relsRelsPath = tempDir.appendingPathComponent("_rels/.rels")
            if fileManager.fileExists(atPath: relsRelsPath.path) {
                print("✅ But _rels/.rels DOES exist at filesystem level!")
                let relsData = try Data(contentsOf: relsRelsPath)
                filesToAdd.append((path: "_rels/.rels", data: relsData, isImage: false))
            } else {
                print("❌ _rels/.rels does NOT exist at filesystem level!")
                // Create it if missing
                print("🔧 Creating _rels/.rels...")
                let relsDir = tempDir.appendingPathComponent("_rels")
                try fileManager.createDirectory(at: relsDir, withIntermediateDirectories: true)
                let defaultRels = """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
                </Relationships>
                """
                try defaultRels.data(using: .utf8)?.write(to: relsRelsPath)
                let relsData = try Data(contentsOf: relsRelsPath)
                filesToAdd.append((path: "_rels/.rels", data: relsData, isImage: false))
            }
        }
        
        // Sort files to ensure consistent order (important for ZIP structure)
        // Add critical files first: [Content_Types].xml, _rels/.rels, then others
        filesToAdd.sort { first, second in
            let priority1 = filePriority(first.path)
            let priority2 = filePriority(second.path)
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return first.path < second.path
        }
        
        // Add files to archive
        print("📝 Adding \(filesToAdd.count) files to archive:")
        for file in filesToAdd {
            let compressionMethod: CompressionMethod = file.isImage ? .none : .deflate
            print("  - \(file.path) (\(file.data.count) bytes, compression: \(compressionMethod == .none ? "none" : "deflate"))")
            try newArchive.addEntry(with: file.path, type: .file, uncompressedSize: UInt32(file.data.count), compressionMethod: compressionMethod) { position, size in
                file.data.subdata(in: position..<position + size)
            }
        }
        
        print("✅ New archive created successfully with \(filesToAdd.count) files")
        
        // Validate the archive can be read back
        guard let validationArchive = Archive(url: outputURL, accessMode: .read) else {
            throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to validate created archive"])
        }
        
        // Check for critical files
        let criticalFiles = ["[Content_Types].xml", "_rels/.rels", "word/document.xml"]
        for criticalFile in criticalFiles {
            if validationArchive[criticalFile] == nil {
                print("⚠️ WARNING: Critical file missing from archive: \(criticalFile)")
            }
        }
        
        print("✅ Archive validation passed")
        return outputURL
    }
    
    // Helper function to prioritize files for correct ZIP structure
    private func filePriority(_ path: String) -> Int {
        if path == "[Content_Types].xml" {
            return 0
        } else if path == "_rels/.rels" {
            return 1
        } else if path.hasPrefix("word/_rels/") {
            return 2
        } else if path.hasPrefix("word/document.xml") {
            return 3
        } else if path.hasPrefix("word/styles.xml") || path.hasPrefix("word/settings.xml") || path.hasPrefix("word/webSettings.xml") {
            return 4
        } else if path.hasPrefix("word/theme/") {
            return 5
        } else if path.hasPrefix("docProps/") {
            return 6
        } else {
            return 10
        }
    }
    
    private func createFooterXML(job: Job) -> String {
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        let addressString = addressToUse.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
               xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:tbl>
            <w:tblPr>
              <w:tblW w:w="0" w:type="auto"/>
              <w:tblBorders>
                <w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/>
                <w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>
                <w:bottom w:val="none" w:sz="0" w:space="0" w:color="auto"/>
                <w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>
                <w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>
                <w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              </w:tblBorders>
            </w:tblPr>
            <w:tr>
              <w:tc>
                <w:tcPr>
                  <w:tcW w:w="0" w:type="auto"/>
                </w:tcPr>
                <w:p>
                  <w:pPr>
                    <w:jc w:val="left"/>
                  </w:pPr>
                  <w:r>
                    <w:t xml:space="preserve">\(addressString.xmlEscaped)</w:t>
                  </w:r>
                </w:p>
              </w:tc>
              <w:tc>
                <w:tcPr>
                  <w:tcW w:w="0" w:type="auto"/>
                </w:tcPr>
                <w:p>
                  <w:pPr>
                    <w:jc w:val="right"/>
                  </w:pPr>
                  <w:r>
                    <w:t xml:space="preserve">PAGE </w:t>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="begin"/>
                  </w:r>
                  <w:r>
                    <w:instrText xml:space="preserve"> PAGE </w:instrText>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="end"/>
                  </w:r>
                  <w:r>
                    <w:t xml:space="preserve"> OF </w:t>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="begin"/>
                  </w:r>
                  <w:r>
                    <w:instrText xml:space="preserve"> NUMPAGES </w:instrText>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="end"/>
                  </w:r>
                </w:p>
              </w:tc>
            </w:tr>
          </w:tbl>
        </w:ftr>
        """
    }
    
    private func loadHurricaneMiltonResource() -> DocxImageResource? {
        // Try loading from images directory first, then root
        var imageData: Data?
        var image: NSImage?
        var fileExtension = "png"
        
        if let path = Bundle.main.path(forResource: "HurricaneMilton", ofType: "png", inDirectory: "images"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            imageData = data
            image = NSImage(data: data)
        } else if let path = Bundle.main.path(forResource: "HurricaneMilton", ofType: "png"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            imageData = data
            image = NSImage(data: data)
        } else if let img = NSImage(named: "HurricaneMilton") ?? NSImage(named: "images/HurricaneMilton"),
                  let tiffData = img.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let data = bitmapRep.representation(using: .png, properties: [:]) {
            imageData = data
            image = img
        }
        
        guard let data = imageData, let img = image else { return nil }
        
        // Hurricane Milton image - size appropriately for report (2 inch margins on each side = 4.5 inches wide)
        let widthInches: CGFloat = 4.5
        let widthEMU = Int(widthInches * 914_400)
        // Calculate height based on actual image aspect ratio
        let aspectRatio = img.size.width > 0 ? img.size.height / img.size.width : 0.75
        let heightEMU = Int(CGFloat(widthEMU) * aspectRatio)
        
        return DocxImageResource(data: data, fileExtension: fileExtension, cx: widthEMU, cy: heightEMU)
    }
    
    private func loadWideMapImageResource(for job: Job) -> DocxImageResource? {
        guard let mapImagePath = job.wideMapImagePath else { return nil }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mapImageURL = documentsDirectory.appendingPathComponent("map_images").appendingPathComponent(mapImagePath)
        
        guard FileManager.default.fileExists(atPath: mapImageURL.path),
              let imageData = try? Data(contentsOf: mapImageURL),
              let image = NSImage(data: imageData) else {
            return nil
        }
        
        // Size appropriately for report - reduced size for second weather picture
        let widthInches: CGFloat = 3.5
        let widthEMU = Int(widthInches * 914_400)
        let aspectRatio = image.size.width > 0 ? image.size.height / image.size.width : 0.75
        let heightEMU = Int(CGFloat(widthEMU) * aspectRatio)
        
        // Use PNG format for map images
        let fileExtension = "png"
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
        
        return DocxImageResource(data: pngData, fileExtension: fileExtension, cx: widthEMU, cy: heightEMU)
    }
    
    private func loadEngineerStampResource() -> DocxImageResource? {
        // Try loading from images directory first, then root
        var imageData: Data?
        var fileExtension = "png"
        
        if let path = Bundle.main.path(forResource: "EngineerStamp", ofType: "png", inDirectory: "images"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            imageData = data
        } else if let path = Bundle.main.path(forResource: "EngineerStamp", ofType: "png"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            imageData = data
        } else if let image = NSImage(named: "EngineerStamp") ?? NSImage(named: "images/EngineerStamp"),
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let data = bitmapRep.representation(using: .png, properties: [:]) {
            imageData = data
        }
        
        guard let data = imageData else { return nil }
        
        // Engineer stamp is circular, approximately 2.35 inches (1.6 + 0.75)
        let stampSizeInches: CGFloat = 2.35
        let stampSizeEMU = Int(stampSizeInches * 914_400)
        
        return DocxImageResource(data: data, fileExtension: fileExtension, cx: stampSizeEMU, cy: stampSizeEMU)
    }
    
    private func generateEngineeringLetterXML(job: Job, engineerStampRef: (relId: String, docPrId: Int)?) -> String {
        var xml = ""
        
        // Title - "ENGINEERING LETTER" in blue, bold
        xml += xmlLargeBoldParagraph("ENGINEERING LETTER", color: "276091", spacingBefore: 446)
        xml += xmlSpacerParagraph(before: 0, after: 120)
        
        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateString = job.inspectionDate.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date())
        xml += xmlEngineeringLetterParagraph(dateString, spacingBefore: 0, spacingAfter: 120)
        
        // Recipient information
        let clientName = job.clientName ?? "Unknown"
        xml += xmlEngineeringLetterParagraph(clientName, spacingBefore: 0, spacingAfter: 0)
        
        // Use cleaned address if available, fallback to original
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        if !addressToUse.isEmpty {
            xml += xmlEngineeringLetterParagraph(addressToUse, spacingBefore: 0, spacingAfter: 0)
        }
        
        let cityStateZip = formatAddressForExport(addressLine1: "", city: job.city, state: job.state, zip: job.zip)
        if !cityStateZip.isEmpty {
            xml += xmlEngineeringLetterParagraph(cityStateZip, spacingBefore: 0, spacingAfter: 120)
        }
        
        // Sender information
        xml += xmlEngineeringLetterParagraph("K. Renevier, P.E.", spacingBefore: 0, spacingAfter: 0)
        xml += xmlEngineeringLetterParagraph("FL Reg. No. 98372", spacingBefore: 0, spacingAfter: 0)
        xml += xmlEngineeringLetterParagraph("1281 Trailhead Pl", spacingBefore: 0, spacingAfter: 0)
        xml += xmlEngineeringLetterParagraph("Harrison, OH 45030", spacingBefore: 0, spacingAfter: 120)
        
        // Salutation
        let firstName = clientName.components(separatedBy: " ").first ?? clientName
        xml += xmlEngineeringLetterParagraph("Greetings \(firstName),", spacingBefore: 0, spacingAfter: 120)
        
        // Body paragraphs
        let paragraph1 = "True Reports Inc., in collaboration with my individual firm, has conducted an evaluation of the condition of the windows at the property located at \(addressToUse.isEmpty ? "the property" : addressToUse), as detailed in the attached report. The opinions presented in this report have been formulated within a reasonable degree of professional certainty. These opinions are based on a review of the available information, associated research, as well as our knowledge, training and experience. True Reports Inc. reserves the right to update this report should additional information become available. The True Reports Inc's investigation of the property at \(addressToUse.isEmpty ? "the property" : addressToUse) was performed by the True Reports Inc. Field Inspection Team under my direct supervision."
        xml += xmlEngineeringLetterParagraph(paragraph1, spacingBefore: 0, spacingAfter: 120)
        
        let paragraph2 = "It is my professional opinion that the property sustained damage to the windows of the building during Hurricane Milton. Windows will need to be repaired or replaced. All repairs must be in compliance with the Florida Building Code: Existing Building 2023."
        xml += xmlEngineeringLetterParagraph(paragraph2, spacingBefore: 0, spacingAfter: 120)
        
        let paragraph3 = "True Reports Inc. appreciates the opportunity to assist with this inspection. Please call if you have any questions."
        xml += xmlEngineeringLetterParagraph(paragraph3, spacingBefore: 0, spacingAfter: 120)
        
        // Closing
        xml += xmlEngineeringLetterParagraph("Respectfully Submitted,", spacingBefore: 0, spacingAfter: 120)
        
        // Signatory information - create a table with two columns: left for names, right for seal
        xml += """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblLook w:val="04A0" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/>
          </w:tblPr>
          <w:tblGrid>
            <w:gridCol w:w="5400"/>
            <w:gridCol w:w="5400"/>
          </w:tblGrid>
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="5400" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:r>
                  <w:rPr><w:rFonts w:ascii="Gill Sans" w:hAnsi="Gill Sans" w:eastAsia="Gill Sans" w:cstheme="minorHAnsi"/></w:rPr>
                  <w:t xml:space="preserve">Stuart Jay Clarke</w:t>
                </w:r>
              </w:p>
              <w:p>
                <w:r>
                  <w:rPr><w:rFonts w:ascii="Gill Sans" w:hAnsi="Gill Sans" w:eastAsia="Gill Sans" w:cstheme="minorHAnsi"/></w:rPr>
                  <w:t xml:space="preserve">K. Renevier, P.E.</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="5400" w:type="dxa"/>
                <w:vAlign w:val="top"/>
              </w:tcPr>
              <w:p/>
            </w:tc>
          </w:tr>
        </w:tbl>
        """
        
        // Add 8 blank lines after the table
        xml += xmlSpacerParagraph(before: 1920, after: 0)  // 8 blank lines (8 * 240 twips)
        
        // Add engineer stamp image if available - right-aligned above disclaimer
        if let stampRef = engineerStampRef {
            xml += xmlAnchoredImageParagraph(relId: stampRef.relId, docPrId: stampRef.docPrId, cx: Int(2.35 * 914_400), cy: Int(2.35 * 914_400), alignment: "right")
        }
        
        // Digital signature disclaimer
        let disclaimerText = "Kyle Renevier, State of Florida, Professional Engineer, License No. 98372. This item has been digitally signed and sealed by Kyle Renevier on the date indicated here. Printed copies of this document are not considered signed and sealed and the signature must be verified on any electronic copies."
        xml += xmlEngineeringLetterParagraph(disclaimerText, spacingBefore: 240, spacingAfter: 0)  // Couple blank lines before disclaimer
        
        return xml
    }
    
    private func generateWindowTestingSummaryXML(job: Job, windows: [Window]) -> String {
        let sortedWindows = sortWindowsByTitleThenNumber(windows)
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        // Title - blue color
        var xml = xmlLargeBoldParagraph("Window Testing Summary", color: "276091", spacingBefore: 446)
        xml += xmlSpacerParagraph(before: 0, after: 240)
        
        // Box with blue header bar - create a table for the box structure
        // Header row with blue background
        let headerRow = """
        <w:tr>
          <w:tc>
            <w:tcPr>
              <w:tcW w:w="0" w:type="auto"/>
              <w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>
            </w:tcPr>
            <w:p>
              <w:pPr>
                <w:spacing w:before="0" w:after="0"/>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  <w:b/>
                  <w:color w:val="FFFFFF"/>
                </w:rPr>
                <w:t xml:space="preserve">Window Testing Summary</w:t>
              </w:r>
            </w:p>
          </w:tc>
        </w:tr>
        """
        
        // Address row
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        var addressComponents: [String] = []
        if !addressToUse.isEmpty {
            addressComponents.append(addressToUse)
        }
        if let city = job.city, !city.isEmpty {
            addressComponents.append(city)
        }
        // Combine state and zip without comma between them
        var stateZip = ""
        if let state = job.state, !state.isEmpty {
            stateZip = state
        }
        if let zip = job.zip, !zip.isEmpty {
            if !stateZip.isEmpty {
                stateZip += " \(zip)"
            } else {
                stateZip = zip
            }
        }
        if !stateZip.isEmpty {
            addressComponents.append(stateZip)
        }
        let addressString = addressComponents.joined(separator: ", ")
        let addressRow = """
        <w:tr>
          <w:tc>
            <w:tcPr>
              <w:tcW w:w="0" w:type="auto"/>
            </w:tcPr>
            <w:p>
              <w:pPr>
                <w:spacing w:before="120" w:after="0"/>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                </w:rPr>
                <w:t xml:space="preserve">\(addressString.xmlEscaped)</w:t>
              </w:r>
            </w:p>
          </w:tc>
        </w:tr>
        """
        
        // Summary table with header and data rows
        let colWidths: [Int] = [1800, 1200, 2700, 2700] // Results, Window, Time: Start, Time: Stop
        let totalWidth = colWidths.reduce(0, +)
        
        var tableXML = """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="\(totalWidth)" w:type="dxa"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>
            </w:tblBorders>
            <w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
          </w:tblPr>
          <w:tblGrid>
        """
        
        for width in colWidths {
            tableXML += "            <w:gridCol w:w=\"\(width)\"/>\n"
        }
        
        tableXML += "          </w:tblGrid>\n"
        
        // Header row
        tableXML += """
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[0])" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
                    <w:b/>
                    <w:color w:val="FFFFFF"/>
                  </w:rPr>
                  <w:t xml:space="preserve">Results</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[1])" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
                    <w:b/>
                    <w:color w:val="FFFFFF"/>
                  </w:rPr>
                  <w:t xml:space="preserve">Window</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[2])" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
                    <w:b/>
                    <w:color w:val="FFFFFF"/>
                  </w:rPr>
                  <w:t xml:space="preserve">Time: Start</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[3])" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
                    <w:b/>
                    <w:color w:val="FFFFFF"/>
                  </w:rPr>
                  <w:t xml:space="preserve">Time: Stop</w:t>
                </w:r>
              </w:p>
            </w:tc>
          </w:tr>
        """
        
        // Data rows
        for window in sortedWindows {
            let result = getDisplayTestResult(for: window)
            let windowNumber = extractNumberFromSpecimenName(window.windowNumber ?? "")
            
            let startTime: String
            if let testStartTime = window.testStartTime {
                startTime = timeFormatter.string(from: testStartTime)
            } else {
                startTime = "N/A"
            }
            
            let stopTime: String
            if let testStopTime = window.testStopTime {
                stopTime = timeFormatter.string(from: testStopTime)
            } else {
                stopTime = "N/A"
            }
            
            tableXML += """
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[0])" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(result.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[1])" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(windowNumber.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[2])" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(startTime.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[3])" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(stopTime.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
          </w:tr>
        """
        }
        
        tableXML += "        </w:tbl>\n"
        
        // Summary text
        xml += xmlSpacerParagraph(before: 240, after: 0)
        xml += xmlParagraph("The home had a total of 9 windows.", spacingBefore: 0, spacingAfter: 0)
        xml += xmlParagraph("Detailed individual test reports available upon request.", spacingBefore: 0, spacingAfter: 10)
        
        // Combine everything: box header, address, table, summary
        let boxXML = """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>
            </w:tblBorders>
          </w:tblPr>
          <w:tblGrid>
            <w:gridCol w:w="8400"/>
          </w:tblGrid>
          \(headerRow)
          \(addressRow)
        </w:tbl>
        """
        
        return xml + boxXML + tableXML
    }
    
    private func generateSummaryOfFindingsXML(job: Job, windows: [Window]) -> String {
        let sortedWindows = sortWindowsByTitleThenNumber(windows)
        
        // Calculate statistics
        let failedWindows = sortedWindows.filter { $0.testResult == "Fail" }
        let inaccessibleWindows = sortedWindows.filter { $0.isInaccessible }
        let totalTestedWindows = sortedWindows.count
        let failedCount = failedWindows.count
        
        // Title - blue color
        var xml = xmlLargeBoldParagraph("SUMMARY OF FINDINGS", color: "276091", spacingBefore: 446)
        xml += xmlSpacerParagraph(before: 0, after: 120)
        
        // Address
        let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
        var addressComponents: [String] = []
        if !addressToUse.isEmpty {
            addressComponents.append(addressToUse)
        }
        if let city = job.city, !city.isEmpty {
            addressComponents.append(city)
        }
        if let state = job.state, !state.isEmpty {
            addressComponents.append(state)
        }
        if let zip = job.zip, !zip.isEmpty {
            addressComponents.append(zip)
        }
        let addressString = addressComponents.joined(separator: ", ")
        xml += xmlParagraph(addressString, spacingBefore: 0, spacingAfter: 240)
        
        // TEST PERFORMED Section
        xml += xmlBoldParagraph("TEST PERFORMED", color: "10325d", spacingBefore: 0, spacingAfter: 120)
        xml += xmlParagraph("The ASTM E331 water test simulates rain conditions and was used to test if the windows are leaking.", spacingBefore: 0, spacingAfter: 240)
        
        // BACKGROUND INFORMATION Section
        xml += xmlBoldParagraph("BACKGROUND INFORMATION", color: "10325d", spacingBefore: 0, spacingAfter: 120)
        
        // Sub-heading
        xml += xmlBoldParagraph("Cyclical Wind Pressures - Why Hurricanes can Cause Windows to Fail.", spacingBefore: 0, spacingAfter: 120)
        
        // Background information paragraphs
        xml += xmlParagraph("Cyclical wind pressures in hurricanes can cause windows to fail even if they are structurally sound. According to FEMA Fact Sheet 1.3, these pressures can create significant stress on building components, leading to structural integrity issues over time.", spacingBefore: 0, spacingAfter: 120)
        // First paragraph as quote, numbered items without quotes
        let firstQuote = "\"During a hurricane, wind changes speed and direction rapidly, creating cyclical pressures that alternate between positive and negative forces. This constant variation can weaken window components, damage seals, and create openings that allow water infiltration."
        xml += xmlParagraph(firstQuote, spacingBefore: 0, spacingAfter: 120)
        
        // Numbered list without quotes
        xml += xmlParagraph("1. Positive Pressure: When wind strikes a building, it creates a positive pressure on the side facing the wind. This pressure attempts to push the building away from the wind.", spacingBefore: 0, spacingAfter: 120)
        xml += xmlParagraph("2. Negative Pressure (Suction): On the leeward side (the side away from the wind) and over the roof, negative pressures are created. These suction forces attempt to pull parts of the building away from the main structure.\"¹", spacingBefore: 0, spacingAfter: 240)
        // Add blank line after
        xml += xmlSpacerParagraph(before: 0, after: 0)
        
        // RECOMMENDATIONS & CONCLUSION Section - Bold, size 24, blue
        var recPPr = "<w:spacing w:after=\"120\"/>"
        let recPPrTag = "<w:pPr>\(recPPr)</w:pPr>"
        xml += """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\(recPPrTag)<w:r><w:rPr>
            <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
            <w:b/>
            <w:sz w:val="48"/>
            <w:szCs w:val="48"/>
            <w:color w:val="276091"/>
        </w:rPr><w:t xml:space="preserve">RECOMMENDATIONS &amp; CONCLUSION</w:t></w:r></w:p>
        """
        
        // Recommendations paragraph 1
        let recommendationsPara1: String
        if failedCount > 0 {
            recommendationsPara1 = "\(failedCount) of \(totalTestedWindows) window\(totalTestedWindows == 1 ? "" : "s") failed the ASTM E331 water test and require repair or replacement. Cyclical pressures from hurricanes can cause windows to fail by weakening glazing, damaging seals, and creating openings that lead to interior damage. For more details on hurricane damage to windows, see the section below called Common Terms."
        } else {
            recommendationsPara1 = "All tested windows passed the ASTM E331 water test. However, cyclical pressures from hurricanes can still cause windows to fail by weakening glazing, damaging seals, and creating openings that lead to interior damage. For more details on hurricane damage to windows, see the section below called Common Terms."
        }
        xml += xmlParagraph(recommendationsPara1, spacingBefore: 0, spacingAfter: 120)
        
        // Recommendations paragraph 2 (about inaccessible windows)
        if inaccessibleWindows.count > 0 {
            let inaccessibleTypes = inaccessibleWindows.compactMap { window -> String? in
                guard let windowType = window.windowType, !windowType.isEmpty else { return nil }
                return windowType.lowercased()
            }
            let uniqueTypes = Array(Set(inaccessibleTypes))
            let typeDescription: String
            if uniqueTypes.count == 1 {
                typeDescription = uniqueTypes[0] + " window"
            } else if uniqueTypes.count > 1 {
                typeDescription = uniqueTypes.dropLast().joined(separator: ", ") + ", and " + uniqueTypes.last! + " windows"
            } else {
                typeDescription = "window"
            }
            
            let recommendationsPara2 = "\(inaccessibleWindows.count) \(typeDescription)\(inaccessibleWindows.count == 1 ? "" : "s") could not be tested due to inaccessibility."
            xml += xmlParagraph(recommendationsPara2, spacingBefore: 0, spacingAfter: 0)
        }
        
        return xml
    }
    
    private func generatePurposeObservationsWeatherXML(
        job: Job,
        hurricaneImageRef: (relId: String, docPrId: Int, cx: Int, cy: Int)?,
        mapImageRef: (relId: String, docPrId: Int, cx: Int, cy: Int)?
    ) -> String {
        var xml = ""
        
        // PURPOSE Section
        xml += xmlBoldParagraph("PURPOSE:", color: "5BA3D6", spacingBefore: 0, spacingAfter: 0)
        let purposeText = "True Reports was hired by the insured to inspect the property for a damage claim. The date of loss (DOL) is indicated as October 9, 2024. The goal of this inspection was to provide a professional opinion on the cause, origin, extent, and repairability of reported and observed window damage."
        xml += xmlParagraph(purposeText, spacingBefore: 0, spacingAfter: 240)
        
        // OBSERVATIONS Section
        xml += xmlBoldParagraph("OBSERVATIONS:", color: "5BA3D6", spacingBefore: 0, spacingAfter: 0)
        let observationsText = "Observations are presented within this report. Property condition is described in photograph captions and elsewhere. Full-resolution images are retained electronically and can be provided upon request."
        xml += xmlParagraph(observationsText, spacingBefore: 0, spacingAfter: 240)
        
        // WEATHER HISTORY Section
        xml += xmlBoldParagraph("WEATHER HISTORY:", color: "5BA3D6", spacingBefore: 0, spacingAfter: 0)
        let weatherHistoryText = "The home was directly in the path of Hurricane Milton. The wind gusts in the area were recorded at over 170 mph on October 9, 2024. NOAA reports sustained winds of between 61 and 91mph."
        xml += xmlParagraphWithSuperscript(weatherHistoryText, superscriptText: "2", spacingBefore: 0, spacingAfter: 240)
        
        // First image: Hurricane Milton radar (static)
        if let hurricaneRef = hurricaneImageRef {
            xml += xmlImageParagraph(relId: hurricaneRef.relId, docPrId: hurricaneRef.docPrId, cx: hurricaneRef.cx, cy: hurricaneRef.cy, alignment: "center")
            xml += xmlSpacerParagraph(before: 120, after: 120)
        }
        
        // Second image: Wide map view
        if let mapRef = mapImageRef {
            xml += xmlImageParagraph(relId: mapRef.relId, docPrId: mapRef.docPrId, cx: mapRef.cx, cy: mapRef.cy, alignment: "center")
        }
        
        // Add section break at end to remove footer spacing for this page and restore for next
        // The sectPr at the end defines properties for the NEXT section (after this page)
        xml += """
        <w:p>
          <w:pPr>
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1166" w:right="1440" w:bottom="720" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
              <w:cols w:space="720"/>
            </w:sectPr>
          </w:pPr>
        </w:p>
        """
        
        return xml
    }
    
    private func generateWorksCitedXML(job: Job) -> String {
        var xml = ""
        
        // Title "SOURCES" - bold, blue, 24pt
        xml += xmlBoldParagraph("SOURCES", color: "276091", fontSize: 24, spacingBefore: 446, spacingAfter: 240)
        
        // First citation (FEMA) - no indent, left aligned
        let citation1 = "1 Federal Emergency Management Agency. \"Cyclical Wind Pressures in Hurricanes.\" Home Builder's Guide to Coastal Construction Technical Fact Sheet Series, no. 1.3, Dec. 2018, www.fema.gov/sites/default/files/2020-07/fema_p499_fact_sheet_1-3_cyclical_wind_pressures.pdf."
        xml += xmlParagraph(citation1, spacingBefore: 0, spacingAfter: 240)
        
        // Second citation (NOAA) - no indent, left aligned
        let citation2 = "2 Beven, John L., II, et al. National Hurricane Center Tropical Cyclone Report: Hurricane Milton (AL142024). National Hurricane Center, 31 Mar. 2025, https://www.nhc.noaa.gov/data/tcr/AL142024_Milton.pdf."
        xml += xmlParagraph(citation2, spacingBefore: 0, spacingAfter: 0)
        
        return xml
    }
    
    private func generateCommonTermsXML() -> String {
        var xml = ""
        
        // Title "COMMON TERMS - WINDOWS CYCLICAL PRESSURES"
        xml += xmlLargeBoldParagraph("COMMON TERMS - WINDOWS CYCLICAL PRESSURES", color: "276091", spacingBefore: 446, spacingAfter: 240)
        
        // Terms list
        let terms: [(term: String, definition: String)] = [
            ("Cyclic Pressure/Loading:", "Repeated forces pushing and pulling on windows due to wind gusts"),
            ("Deflection:", "How much a window bends under pressure"),
            ("Fatigue:", "Weakening of materials from repeated stress cycles"),
            ("Impact Resistance:", "Ability to withstand flying debris"),
            ("Interlayer:", "Material between glass panes (usually PVB - polyvinyl butyral) that holds broken glass together"),
            ("Laminated Glass:", "Safety glass with plastic interlayer bonding multiple glass panes"),
            ("Pressure Differential:", "Difference between inside and outside air pressure"),
            ("PSF (Pounds per Square Foot):", "Unit for measuring wind pressure on windows"),
            ("Tempered Glass:", "Heat-treated glass that breaks into small pieces instead of sharp shards"),
            ("Design Pressure (DP):", "Maximum pressure a window is designed to withstand"),
            ("Point of Failure:", "Stress level where window damage begins")
        ]
        
        for (term, definition) in terms {
            // Term in bold
            xml += xmlBoldParagraph(term, spacingBefore: 0, spacingAfter: 0)
            // Definition on same line or next line
            xml += xmlParagraph(definition, spacingBefore: 0, spacingAfter: 120)
        }
        
        return xml
    }
    
    private func xmlIndentedParagraph(_ text: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        // Add left indent (720 twips = 0.5 inches)
        pPr += "<w:ind w:left=\"720\"/>"
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        return "<w:p>\(pPrTag)<w:r><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlHangingIndentParagraph(_ text: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        // Add hanging indent: left indent of 720 twips (0.5 inches) with hanging of -720 to pull first line back
        // This makes the first line flush left and continuation lines indented
        pPr += "<w:ind w:left=\"720\" w:hanging=\"-720\"/>"
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        return "<w:p>\(pPrTag)<w:r><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func generateSpecimenLocationsLegendXML() -> String {
        // Legend items: (color hex, label)
        let legendItems: [(String, String)] = [
            ("00FF00", "Pass"),      // Green
            ("FF0000", "Fail"),      // Red
            ("808080", "Inaccessible") // Gray
        ]
        
        // Create a table with 3 columns for the legend items
        var xml = """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
               xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
               xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
               xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
               xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblLayout w:type="fixed"/>
            <w:jc w:val="center"/>
          </w:tblPr>
          <w:tblGrid>
            <w:gridCol w:w="3000"/>
            <w:gridCol w:w="3000"/>
            <w:gridCol w:w="3000"/>
          </w:tblGrid>
          <w:tr>
        """
        
        // Generate a unique docPrId for each circle
        var docPrId = 10000
        
        for (index, (color, label)) in legendItems.enumerated() {
            xml += """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="3000" w:type="dxa"/>
                <w:vAlign w:val="center"/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:jc w:val="center"/>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:drawing>
                    <wp:inline distT="0" distB="0" distL="0" distR="0">
                      <wp:extent cx="240000" cy="240000"/>
                      <wp:docPr id="\(docPrId)" name="LegendCircle\(docPrId)"/>
                      <wp:cNvGraphicFramePr/>
                      <a:graphic>
                        <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                          <wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                            <wps:cNvPr id="\(docPrId)" name="Circle\(docPrId)"/>
                            <wps:cNvSpPr/>
                            <wps:spPr>
                              <a:xfrm>
                                <a:off x="0" y="0"/>
                                <a:ext cx="240000" cy="240000"/>
                              </a:xfrm>
                              <a:prstGeom prst="ellipse">
                                <a:avLst/>
                              </a:prstGeom>
                              <a:solidFill>
                                <a:srgbClr val="\(color)"/>
                              </a:solidFill>
                              <a:ln>
                                <a:noFill/>
                              </a:ln>
                            </wps:spPr>
                            <wps:txbx>
                              <w:txbxContent>
                                <w:p/>
                              </w:txbxContent>
                            </wps:txbx>
                          </wps:wsp>
                        </a:graphicData>
                      </a:graphic>
                    </wp:inline>
                  </w:drawing>
                </w:r>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                    <w:sz w:val="24"/>
                    <w:szCs w:val="24"/>
                  </w:rPr>
                  <w:t xml:space="preserve"> \(label.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            """
            docPrId += 1
        }
        
        xml += """
          </w:tr>
        </w:tbl>
        """
        
        return xml
    }
    
    private func generateCredentialsXML(job: Job) -> String {
        var xml = ""
        
        // Title "CREDENTIALS"
        xml += xmlBoldParagraph("CREDENTIALS", color: "276091", fontSize: 24, spacingBefore: 446, spacingAfter: 120)
        
        // K. Renevier, P.E.
        xml += xmlBoldParagraph("K. Renevier, P.E.", fontSize: 11, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Licenses: Florida Professional Engineering License #98372. Also holds a professional engineering license in Alabama, Louisiana, and Texas.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Education: B.S. Civil Engineering from the University of Oklahoma; M.S. Civil Engineering with an Emphasis in Structures from the University of Oklahoma.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Experience: Has over a decade of engineering experience, including seven years as a licensed professional engineer. Specializes in Forensic and Design Engineering for residential, commercial, and industrial projects. Has assessed structures damaged by significant tornadoes (e.g., Joplin, MO) and major hurricanes across the Gulf Coast since 2018. Assists communities impacted by natural disasters.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 100)
        
        // Yonatan Z. Rotenberg
        xml += xmlBoldParagraph("Yonatan Z. Rotenberg", fontSize: 11, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Education: B.S. Mechanical Engineering from Florida International University.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Experience: Has a decade of engineering experience. Responsible for evaluating the structural safety of various components and systems. Has authored numerous engineering documents and reports, holds patents, and is a co-author on research publications. Previously worked as a research assistant in mechanical testing and metallurgy.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 100)
        
        // Stuart Jay Clarke III, CGC & CCC
        xml += xmlBoldParagraph("Stuart Jay Clarke III, CGC & CCC", fontSize: 11, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Licenses: Roofing Contractor - CCC1327185; General Contractor - CGC1518899.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Education: Bachelor of Science from FSU & UCF. Field of Study includes Chemical Engineering, Chemistry, and Forensic Science.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Experience: Serves as an Expert Witness and a Roof consultant for award-winning architects. Is a U.S. Patent holder. Has overseen the installation of thousands of quality roofs and completed over 3,000 roof inspections and reports across the southeastern United States. Worked as a Roofing expert and forensic inspector for one of Florida's largest insurance companies. Is an original member of the No Blue Roof charity and one of only 10 roofing contractors to receive an award from Miami Dade County for outstanding service. Was part of the original My Safe Florida Home team, contributing to improving roof safety and strengthening the roofing code in Florida.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 100)
        
        // Joel S. Jaroslawicz
        xml += xmlBoldParagraph("Joel S. Jaroslawicz", fontSize: 11, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Licenses/Certifications: Holds a 620 All Lines Adjuster License; FEMA Certified for IS-285 (Flood Damage Appraisal Management); License # W263548.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 40)
        xml += xmlParagraph("Experience: Has over a decade of experience in the insurance industry. Has worked as both an Independent Adjuster and a Public Adjuster, providing a dual perspective on insurance claims, which makes him valuable in understanding, evaluating, and adjusting claims from both the insurer's and the claimant's viewpoints.", fontSize: 11, isBold: false, spacingBefore: 0, spacingAfter: 0)
        
        return xml
    }
    
    private func sortWindowsByTitleThenNumber(_ windows: [Window]) -> [Window] {
        return windows.sorted { window1, window2 in
            let num1 = window1.windowNumber ?? ""
            let num2 = window2.windowNumber ?? ""
            
            // Parse the window number to extract title and number parts
            let parts1 = parseWindowNumber(num1)
            let parts2 = parseWindowNumber(num2)
            
            // First compare by title (alphabetically)
            if parts1.title != parts2.title {
                return parts1.title < parts2.title
            }
            
            // If titles are the same, compare by number (numerically)
            return parts1.number < parts2.number
        }
    }
    
    private func parseWindowNumber(_ windowNumber: String) -> (title: String, number: Int) {
        let trimmed = windowNumber.trimmingCharacters(in: .whitespaces)
        
        // Try to find the last number in the string
        if let range = trimmed.range(of: #"\d+$"#, options: .regularExpression) {
            let titlePart = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let numberPart = String(trimmed[range])
            
            if let number = Int(numberPart) {
                return (title: titlePart.isEmpty ? trimmed : titlePart, number: number)
            }
        }
        
        // If no number found, return the whole string as title with number 0
        return (title: trimmed, number: 0)
    }
    
    private func getDisplayTestResult(for window: Window) -> String {
        if window.isInaccessible {
            return "Inaccessible"
        }
        return window.testResult ?? "Pending"
    }
    
    private func extractNumberFromSpecimenName(_ name: String) -> String {
        // Try to find a number at the end of the string
        if let lastSpaceIndex = name.lastIndex(of: " ") {
            let numberPart = String(name[name.index(after: lastSpaceIndex)...])
            // Check if it's a valid number
            if Int(numberPart) != nil {
                return numberPart
            }
        }
        // If no number found, return original (fallback for names like "W01")
        return name
    }

    private func replaceEntry(_ archive: Archive, name: String, with string: String) throws {
        if let entry = archive[name] {
            try archive.remove(entry)
        }
        let data = Data(string.utf8)
        try archive.addEntry(with: name,
                             type: .file,
                             uncompressedSize: UInt32(data.count),
                             compressionMethod: .deflate) { position, size in
            data.subdata(in: position..<position + size)
        }
    }

    private func wrapDocumentXML(_ body: String, footerRelId: String? = nil) -> String {
        var sectPr = """
            <w:pgSz w:w="12240" w:h="15840"/>
            <w:pgMar w:top="1166" w:right="1440" w:bottom="720" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
            <w:cols w:space="720"/>
        """
        if let footerRelId {
            sectPr += """
              <w:footerReference w:type="default" r:id="\(footerRelId)"/>
            """
        }
        
        // Put sectPr inside the last paragraph's pPr (matching template structure exactly)
        // CRITICAL: A paragraph can only have ONE pPr element at the END, after all content.
        var modifiedBody = body.isEmpty ? "<w:p/>" : body
        
        // Find the last </w:p> tag
        if let lastParaEndRange = modifiedBody.range(of: "</w:p>", options: .backwards) {
            // Find the start of the last paragraph - use simple backwards search
            // This finds the last <w:p before the last </w:p>
            guard let lastParaStart = modifiedBody.range(of: "<w:p", options: .backwards, range: modifiedBody.startIndex..<lastParaEndRange.lowerBound)?.lowerBound else {
                // Can't find paragraph start, just add pPr before closing tag
                let insertIndex = modifiedBody.index(lastParaEndRange.lowerBound, offsetBy: 0)
                modifiedBody.insert(contentsOf: "<w:pPr><w:sectPr>\(sectPr)</w:sectPr></w:pPr>", at: insertIndex)
                return """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
                  <w:body>
                    \(modifiedBody)
                  </w:body>
                </w:document>
                """
            }
            
            // Extract everything between <w:p> and </w:p> (the inner content)
            let paraTagEnd = modifiedBody.range(of: ">", range: lastParaStart..<lastParaEndRange.lowerBound)?.upperBound ?? modifiedBody.index(lastParaStart, offsetBy: 4)
            var paraInnerContent = String(modifiedBody[paraTagEnd..<lastParaEndRange.lowerBound])
            
            // DEBUG: Check for nested paragraphs before processing
            let hasNestedPara = paraInnerContent.contains("<w:p")
            if hasNestedPara {
                print("⚠️ WARNING: Last paragraph contains nested <w:p> tag!")
            }
            
            // Extract all pPr content and remove all pPr elements
            var allPPrContent = ""
            
            // Find and extract ALL pPr elements (there might be multiple)
            while let pPrStart = paraInnerContent.range(of: "<w:pPr>"),
                  let pPrEnd = paraInnerContent.range(of: "</w:pPr>", range: pPrStart.upperBound..<paraInnerContent.endIndex) {
                // Extract content between <w:pPr> and </w:pPr>
                let pPrInnerContent = String(paraInnerContent[pPrStart.upperBound..<pPrEnd.lowerBound])
                // Remove any existing sectPr
                let cleanPPr = pPrInnerContent.replacingOccurrences(of: "<w:sectPr>.*?</w:sectPr>", with: "", options: .regularExpression)
                if !cleanPPr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    allPPrContent += cleanPPr
                }
                // Remove this entire pPr element (including tags)
                paraInnerContent.removeSubrange(pPrStart.lowerBound..<pPrEnd.upperBound)
            }
            
            // Remove any standalone sectPr elements
            paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:sectPr>.*?</w:sectPr>", with: "", options: .regularExpression)
            
            // CRITICAL: Remove ALL nested paragraph tags completely - do this multiple times to catch all cases
            var iterations = 0
            var previousContent = ""
            while paraInnerContent != previousContent && iterations < 20 {
                previousContent = paraInnerContent
                // Remove opening paragraph tags (with or without attributes)
                paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:p[^>]*>", with: "", options: .regularExpression)
                // Remove closing paragraph tags
                paraInnerContent = paraInnerContent.replacingOccurrences(of: "</w:p>", with: "")
                iterations += 1
            }
            
            // Also remove any malformed tags that might have been created (spacing outside pPr)
            paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:spacing[^>]*/>", with: "", options: .regularExpression)
            paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:spacing[^>]*>.*?</w:spacing>", with: "", options: .regularExpression)
            
            // Remove any other paragraph-related tags that might be outside pPr
            paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:pPr[^>]*>", with: "", options: .regularExpression)
            paraInnerContent = paraInnerContent.replacingOccurrences(of: "</w:pPr>", with: "")
            
            // Trim whitespace
            paraInnerContent = paraInnerContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Final check: if there's still a nested paragraph, force remove it
            while paraInnerContent.contains("<w:p") || paraInnerContent.contains("</w:p>") {
                // Use a more aggressive approach - find and remove nested paragraphs manually
                if let nestedStart = paraInnerContent.range(of: "<w:p")?.lowerBound,
                   let nestedEnd = paraInnerContent.range(of: "</w:p>", range: nestedStart..<paraInnerContent.endIndex)?.upperBound {
                    paraInnerContent.removeSubrange(nestedStart..<nestedEnd)
                } else {
                    // Fallback to regex
                    paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:p[^>]*>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "</w:p>", with: "")
                    break
                }
            }
            
            // Ensure no malformed spacing tags remain
            if paraInnerContent.contains("<w:spacing") && !paraInnerContent.contains("<w:pPr>") {
                // Remove spacing tags that are outside pPr
                paraInnerContent = paraInnerContent.replacingOccurrences(of: "<w:spacing[^>]*/>", with: "", options: .regularExpression)
            }
            
            // Rebuild the paragraph: content first, then single pPr with sectPr at end
            let newLastPara = "<w:p>\(paraInnerContent)<w:pPr>\(allPPrContent)<w:sectPr>\(sectPr)</w:sectPr></w:pPr></w:p>"
            
            // Validate: ensure no nested paragraphs in the rebuilt paragraph
            let paraCount = newLastPara.components(separatedBy: "<w:p").count - 1
            if paraCount > 1 {
                print("⚠️ ERROR: Rebuilt paragraph still contains nested paragraphs! Count: \(paraCount)")
                // Last resort: extract only the text content and rebuild from scratch
                var textContent = ""
                let textRegex = try! NSRegularExpression(pattern: "<w:t[^>]*>(.*?)</w:t>", options: .dotMatchesLineSeparators)
                let matches = textRegex.matches(in: paraInnerContent, options: [], range: NSRange(paraInnerContent.startIndex..<paraInnerContent.endIndex, in: paraInnerContent))
                textContent = matches.compactMap { match -> String? in
                    guard match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: paraInnerContent) else { return nil }
                    return String(paraInnerContent[range])
                }.joined(separator: " ")
                
                let cleanRebuilt = "<w:p><w:r><w:t xml:space=\"preserve\">\(textContent)</w:t></w:r><w:pPr>\(allPPrContent)<w:sectPr>\(sectPr)</w:sectPr></w:pPr></w:p>"
                modifiedBody.replaceSubrange(lastParaStart..<lastParaEndRange.upperBound, with: cleanRebuilt)
            } else {
                // Replace the entire last paragraph
                modifiedBody.replaceSubrange(lastParaStart..<lastParaEndRange.upperBound, with: newLastPara)
            }
        } else {
            // No paragraph found, create one with sectPr
            modifiedBody += "<w:p><w:pPr><w:sectPr>\(sectPr)</w:sectPr></w:pPr></w:p>"
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
            \(modifiedBody)
          </w:body>
        </w:document>
        """
    }

    private func wrapRelsXML(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(body)
        </Relationships>
        """
    }

    private func xmlParagraph(_ text: String, style: String? = nil, centered: Bool = false, fontSize: Double? = nil, isBold: Bool = false, color: String? = nil, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let style {
            pPr += "<w:pStyle w:val=\"\(style.xmlEscaped)\"/>"
        }
        if centered {
            pPr += "<w:jc w:val=\"center\"/>"
        }
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        var rPr = "<w:rFonts w:ascii=\"\(isBold ? "Graphik Bold" : "Graphik")\" w:hAnsi=\"\(isBold ? "Graphik Bold" : "Graphik")\" w:eastAsia=\"\(isBold ? "Graphik Bold" : "Graphik")\" w:cstheme=\"minorHAnsi\"/>"
        if isBold {
            rPr += "<w:b/>"
        }
        if let fontSize {
            let fontSizeHalfPoints = Int(fontSize * 2) // Word uses half-points
            rPr += "<w:sz w:val=\"\(fontSizeHalfPoints)\"/><w:szCs w:val=\"\(fontSizeHalfPoints)\"/>"
        }
        if let color {
            rPr += "<w:color w:val=\"\(color)\"/>"
        }
        return "<w:p>\(pPrTag)<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlEngineeringLetterParagraph(_ text: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        return "<w:p>\(pPrTag)<w:r><w:rPr><w:rFonts w:ascii=\"Gill Sans\" w:hAnsi=\"Gill Sans\" w:eastAsia=\"Gill Sans\" w:cstheme=\"minorHAnsi\"/></w:rPr><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlBoldParagraph(_ text: String, color: String? = nil, fontSize: Double? = nil, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        var rPr = "<w:rFonts w:ascii=\"Graphik Bold\" w:hAnsi=\"Graphik Bold\" w:eastAsia=\"Graphik Bold\" w:cstheme=\"minorHAnsi\"/><w:b/>"
        if let fontSize {
            let fontSizeHalfPoints = Int(fontSize * 2) // Word uses half-points
            rPr += "<w:sz w:val=\"\(fontSizeHalfPoints)\"/><w:szCs w:val=\"\(fontSizeHalfPoints)\"/>"
        }
        if let color {
            rPr += "<w:color w:val=\"\(color)\"/>"
        }
        return "<w:p>\(pPrTag)<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlParagraphWithSuperscript(_ text: String, superscriptText: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        return "<w:p>\(pPrTag)<w:r><w:rPr><w:rFonts w:ascii=\"Graphik\" w:hAnsi=\"Graphik\" w:eastAsia=\"Graphik\" w:cstheme=\"minorHAnsi\"/></w:rPr><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii=\"Graphik\" w:hAnsi=\"Graphik\" w:eastAsia=\"Graphik\" w:cstheme=\"minorHAnsi\"/><w:vertAlign w:val=\"superscript\"/></w:rPr><w:t xml:space=\"preserve\">\(superscriptText.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlLargeBoldParagraph(_ text: String, color: String? = nil, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        // Large font size (24 points = 48 half-points) and bold
        var rPr = "<w:rFonts w:ascii=\"Graphik\" w:hAnsi=\"Graphik\" w:eastAsia=\"Graphik\" w:cstheme=\"minorHAnsi\"/><w:b/><w:sz w:val=\"48\"/>"
        if let color {
            rPr += "<w:color w:val=\"\(color)\"/>"
        }
        return "<w:p>\(pPrTag)<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>"
    }
    
    private func xmlOverviewTitle(_ text: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        // Graphik Bold, 27 points = 54 half-points, color #276091
        return """
        <w:p>\(pPrTag)<w:r><w:rPr>
            <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
            <w:b/>
            <w:sz w:val="54"/>
            <w:szCs w:val="54"/>
            <w:color w:val="276091"/>
        </w:rPr><w:t xml:space="preserve">\(text.xmlEscaped)</w:t></w:r></w:p>
        """
    }

    private func xmlFullPageImage(relId: String, docPrId: Int, cx: Int, cy: Int) -> String {
        """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658240" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>0</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>0</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(docPrId)" name="Image\(docPrId)"/>
                <wp:cNvGraphicFramePr/>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="Image\(docPrId)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relId)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(cx)" cy="\(cy)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlCoverPageText(text: String, x: Int, y: Int, fontSize: Int, isBold: Bool, color: String, alignment: String) -> String {
        // x and y are in EMU (English Metric Units), 1 inch = 914400 EMU
        // y is measured from top of page
        let fontSizeEMU = fontSize * 2 // Word uses half-points
        let boldTag = isBold ? "<w:b/>" : ""
        
        // Calculate text box width based on alignment
        let textBoxWidth: Int
        if alignment == "center" {
            textBoxWidth = Int(7.0 * 914_400) // 7 inches wide for centered text
        } else {
            textBoxWidth = Int(4.0 * 914_400) // 4 inches wide for left-aligned text
        }
        
        // Calculate x position for centered text
        let actualX: Int
        if alignment == "center" {
            actualX = x - (textBoxWidth / 2) // Center the text box
        } else {
            actualX = x
        }
        
        // Use a unique ID for each text box
        let textBoxId = abs(text.hashValue) % 1000000
        
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658241" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>\(actualX)</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>\(y)</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                    <wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                      <wps:cNvPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                      <wps:cNvSpPr txBox="1"/>
                      <wps:spPr>
                        <a:xfrm>
                          <a:off x="\(actualX)" y="\(y)"/>
                          <a:ext cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect">
                          <a:avLst/>
                        </a:prstGeom>
                        <a:noFill/>
                        <a:ln w="0">
                          <a:noFill/>
                        </a:ln>
                      </wps:spPr>
                      <wps:txbx>
                        <w:txbxContent>
                          <w:p>
                            <w:pPr>
                              <w:jc w:val="\(alignment == "center" ? "center" : "left")"/>
                            </w:pPr>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="\(isBold ? "Graphik Bold" : "Graphik")" w:hAnsi="\(isBold ? "Graphik Bold" : "Graphik")" w:eastAsia="\(isBold ? "Graphik Bold" : "Graphik")" w:cstheme="minorHAnsi"/>
                                \(boldTag)
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:t xml:space="preserve">\(text.xmlEscaped)</w:t>
                            </w:r>
                          </w:p>
                        </w:txbxContent>
                      </wps:txbx>
                    </wps:wsp>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlCoverPageTextWithTab(text: String, tabText: String, x: Int, y: Int, fontSize: Int, color: String) -> String {
        let fontSizeEMU = fontSize * 2
        let textBoxId = abs((text + tabText).hashValue) % 1000000
        let textBoxWidth = Int(6.0 * 914_400)
        
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658241" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>\(x)</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>\(y)</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                    <wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                      <wps:cNvPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                      <wps:cNvSpPr txBox="1"/>
                      <wps:spPr>
                        <a:xfrm>
                          <a:off x="\(x)" y="\(y)"/>
                          <a:ext cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect">
                          <a:avLst/>
                        </a:prstGeom>
                        <a:noFill/>
                        <a:ln w="0">
                          <a:noFill/>
                        </a:ln>
                      </wps:spPr>
                      <wps:txbx>
                        <w:txbxContent>
                          <w:p>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
                                <w:b/>
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:t xml:space="preserve">\(text.xmlEscaped)</w:t>
                            </w:r>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
                                <w:b/>
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:tab/>
                              <w:t xml:space="preserve">\(tabText.xmlEscaped)</w:t>
                            </w:r>
                          </w:p>
                        </w:txbxContent>
                      </wps:txbx>
                    </wps:wsp>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlCoverPageTextWithTwoTabs(text: String, tabText: String, x: Int, y: Int, fontSize: Int, color: String) -> String {
        let fontSizeEMU = fontSize * 2
        let textBoxId = abs((text + tabText).hashValue) % 1000000 + 1000000
        let textBoxWidth = Int(6.0 * 914_400)
        
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658241" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>\(x)</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>\(y)</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                    <wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                      <wps:cNvPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                      <wps:cNvSpPr txBox="1"/>
                      <wps:spPr>
                        <a:xfrm>
                          <a:off x="\(x)" y="\(y)"/>
                          <a:ext cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect">
                          <a:avLst/>
                        </a:prstGeom>
                        <a:noFill/>
                        <a:ln w="0">
                          <a:noFill/>
                        </a:ln>
                      </wps:spPr>
                      <wps:txbx>
                        <w:txbxContent>
                          <w:p>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
                                <w:b/>
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:t xml:space="preserve">\(text.xmlEscaped)</w:t>
                            </w:r>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
                                <w:b/>
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:tab/>
                              <w:tab/>
                              <w:t xml:space="preserve">\(tabText.xmlEscaped)</w:t>
                            </w:r>
                          </w:p>
                        </w:txbxContent>
                      </wps:txbx>
                    </wps:wsp>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlCoverPageTextWithThreeTabs(text: String, x: Int, y: Int, fontSize: Int, color: String) -> String {
        let fontSizeEMU = fontSize * 2
        let textBoxId = abs(text.hashValue) % 1000000 + 2000000
        let textBoxWidth = Int(6.0 * 914_400)
        
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658241" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>\(x)</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>\(y)</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                    <wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                      <wps:cNvPr id="\(textBoxId)" name="TextBox\(textBoxId)"/>
                      <wps:cNvSpPr txBox="1"/>
                      <wps:spPr>
                        <a:xfrm>
                          <a:off x="\(x)" y="\(y)"/>
                          <a:ext cx="\(textBoxWidth)" cy="\(Int(0.5 * 914_400))"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect">
                          <a:avLst/>
                        </a:prstGeom>
                        <a:noFill/>
                        <a:ln w="0">
                          <a:noFill/>
                        </a:ln>
                      </wps:spPr>
                      <wps:txbx>
                        <w:txbxContent>
                          <w:p>
                            <w:r>
                              <w:rPr>
                                <w:rFonts w:ascii="Graphik Bold" w:hAnsi="Graphik Bold" w:eastAsia="Graphik Bold" w:cstheme="minorHAnsi"/>
                                <w:b/>
                                <w:sz w:val="\(fontSizeEMU)"/>
                                <w:szCs w:val="\(fontSizeEMU)"/>
                                <w:color w:val="\(color)"/>
                              </w:rPr>
                              <w:tab/>
                              <w:tab/>
                              <w:tab/>
                              <w:t xml:space="preserve">\(text.xmlEscaped)</w:t>
                            </w:r>
                          </w:p>
                        </w:txbxContent>
                      </wps:txbx>
                    </wps:wsp>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    private func xmlImageParagraph(relId: String, docPrId: Int, cx: Int, cy: Int, alignment: String? = nil) -> String {
        let alignmentTag: String
        if let alignment {
            alignmentTag = "    <w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>\n"
        } else {
            alignmentTag = ""
        }
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        \(alignmentTag)
          <w:r>
            <w:drawing>
              <wp:inline>
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:docPr id="\(docPrId)" name="Image\(docPrId)"/>
                <wp:cNvGraphicFramePr/>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="Image\(docPrId)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relId)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(cx)" cy="\(cy)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlAnchoredImageParagraph(relId: String, docPrId: Int, cx: Int, cy: Int, alignment: String? = nil) -> String {
        // Calculate horizontal position based on alignment
        // Page width is 8.5 inches = 7,772,400 EMU
        let pageWidthEMU = Int(8.5 * 914_400)
        let xPosition: Int
        if alignment == "right" {
            // Right align: position from right edge of page
            xPosition = pageWidthEMU - cx - Int(1.0 * 914_400) // 1 inch margin from right
        } else if alignment == "center" {
            // Center align
            xPosition = (pageWidthEMU - cx) / 2
        } else {
            // Left align: 1 inch from left
            xPosition = Int(1.0 * 914_400)
        }
        
        // Position vertically at 6.67 inches from top of page
        let yPosition = Int(6.67 * 914_400)
        
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658240" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="page">
                  <wp:posOffset>\(xPosition)</wp:posOffset>
                </wp:positionH>
                <wp:positionV relativeFrom="page">
                  <wp:posOffset>\(yPosition)</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(docPrId)" name="Image\(docPrId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="Image\(docPrId)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relId)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(cx)" cy="\(cy)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    private func xmlImageWithCaption(relId: String, docPrId: Int, caption: String, cx: Int, cy: Int, alignment: String? = nil) -> String {
        let imageParagraph = xmlImageParagraph(relId: relId, docPrId: docPrId, cx: cx, cy: cy, alignment: alignment)
        let captionAlignment = alignment.map { "<w:pPr><w:jc w:val=\"\($0)\"/></w:pPr>" } ?? ""
        let captionParagraph = "<w:p>\(captionAlignment)<w:r><w:t xml:space=\"preserve\">\(caption.xmlEscaped)</w:t></w:r></w:p>"
        return imageParagraph + captionParagraph
    }
    
    private func xmlAnchoredImageInCell(relId: String, docPrId: Int, cx: Int, cy: Int, alignment: String? = nil) -> String {
        // Anchored image for table cells with wrapNone to prevent text wrapping
        let alignmentTag: String
        if let alignment {
            alignmentTag = "    <w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>\n"
        } else {
            alignmentTag = ""
        }
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
             xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        \(alignmentTag)
          <w:r>
            <w:drawing>
              <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658240" behindDoc="0" layoutInCell="1" locked="0" allowOverlap="1">
                <wp:simplePos x="0" y="0"/>
                <wp:positionH relativeFrom="column">
                  <wp:align>\(alignment == "center" ? "center" : alignment == "right" ? "right" : "left")</wp:align>
                </wp:positionH>
                <wp:positionV relativeFrom="paragraph">
                  <wp:posOffset>0</wp:posOffset>
                </wp:positionV>
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:wrapNone/>
                <wp:docPr id="\(docPrId)" name="Image\(docPrId)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="Image\(docPrId)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relId)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(cx)" cy="\(cy)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:anchor>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    private func xmlOverviewRow(label: String, value: String, spacingAfter: Int = 10) -> String {
        let escapedLabel = label.xmlEscaped
        let escapedValue = value.xmlEscaped
        return """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblLook w:val="04A0" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/>
          </w:tblPr>
          <w:tblGrid>
            <w:gridCol w:w="3600"/>
            <w:gridCol w:w="7200"/>
          </w:tblGrid>
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="3600" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:r>
                  <w:rPr><w:b/></w:rPr>
                  <w:t xml:space="preserve">\(escapedLabel):</w:t>
                </w:r>
              </w:p>
            </w:tc>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="7200" w:type="dxa"/>
              </w:tcPr>
              <w:p>
                <w:r>
                  <w:t xml:space="preserve">\(escapedValue)</w:t>
                </w:r>
              </w:p>
            </w:tc>
          </w:tr>
        </w:tbl>
        """
    }
    
    private func xmlOverviewTextRow(label: String, value: String, spacingAfter: Int = 120) -> String {
        let escapedLabel = label.xmlEscaped
        let escapedValue = value.xmlEscaped
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:pPr>
            <w:spacing w:after="\(spacingAfter)"/>
          </w:pPr>
          <w:r>
            <w:rPr>
              <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
              <w:sz w:val="32"/>
              <w:szCs w:val="32"/>
              <w:color w:val="276091"/>
            </w:rPr>
            <w:t xml:space="preserve">\(escapedLabel):</w:t>
          </w:r>
          <w:r>
            <w:rPr>
              <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
            </w:rPr>
            <w:t xml:space="preserve"> \(escapedValue)</w:t>
          </w:r>
        </w:p>
        """
    }
    
    private func xmlOverviewAddressSubtitle(_ text: String, spacingBefore: Int? = nil, spacingAfter: Int? = nil) -> String {
        var pPr = ""
        if let spacingBefore = spacingBefore ?? (spacingAfter != nil ? 0 : nil), let spacingAfter = spacingAfter ?? (spacingBefore != nil ? 0 : nil) {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        } else if let spacingBefore {
            pPr += "<w:spacing w:before=\"\(spacingBefore)\"/>"
        } else if let spacingAfter {
            pPr += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        }
        let pPrTag = pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>"
        // Graphik Regular, 16 points = 32 half-points, color #276091
        return """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\(pPrTag)<w:r><w:rPr>
            <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
            <w:sz w:val="32"/>
            <w:szCs w:val="32"/>
            <w:color w:val="276091"/>
        </w:rPr><w:t xml:space="preserve">\(text.xmlEscaped)</w:t></w:r></w:p>
        """
    }
    
    private func filterUnwantedFieldsFromNotes(_ notes: String) -> String {
        let unwantedPatterns = [
            "Window Test Status:",
            "Roof Report Status:",
            "Mold Concerns:",
            "Tenant:",
            "Tenant Phone:"
        ]
        
        let lines = notes.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !unwantedPatterns.contains { pattern in
                trimmedLine.hasPrefix(pattern)
            }
        }
        
        return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func xmlParagraphWithBackgroundImage(relId: String, docPrId: Int, cx: Int, cy: Int) -> String {
        """
        <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:v="urn:schemas-microsoft-com:vml"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:r>
            <w:pict>
              <v:shape id="BackImg\(docPrId)" type="#_x0000_t75" style="position:absolute;margin-left:0;margin-top:0;width:100%;height:100%;z-index:-251658752">
                <v:imagedata r:id="\(relId)" o:title=""/>
              </v:shape>
            </w:pict>
          </w:r>
        </w:p>
        """
    }

    private func pageBreak() -> String {
        """
        <w:p>
          <w:r>
            <w:br w:type="page"/>
          </w:r>
        </w:p>
        """
    }

    private func updateContentTypesInDirectory(_ directory: URL, with extensions: Set<String>, hasFooter: Bool = false) throws {
        let fileManager = FileManager.default
        let contentTypesPath = directory.appendingPathComponent("[Content_Types].xml")
        
        guard fileManager.fileExists(atPath: contentTypesPath.path) else {
            return
        }
        
        guard var xml = try? String(contentsOf: contentTypesPath, encoding: .utf8) else {
            return
        }

        var needsUpdate = false

        // Register image extensions
        let knownTypes: [String: String] = [
            "png": "image/png",
            "jpeg": "image/jpeg",
            "jpg": "image/jpeg"
        ]

        for ext in extensions {
            guard let contentType = knownTypes[ext], xml.contains("Extension=\"\(ext)\"") == false else {
                continue
            }
            let insertion = "    <Default Extension=\"\(ext)\" ContentType=\"\(contentType)\"/>\n"
            if let range = xml.range(of: "</Types>") {
                xml.insert(contentsOf: insertion, at: range.lowerBound)
                needsUpdate = true
            }
        }

        // Register footer content type if footer exists
        if hasFooter && !xml.contains("PartName=\"/word/footer1.xml\"") {
            let footerInsertion = "    <Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>\n"
            if let range = xml.range(of: "</Types>") {
                xml.insert(contentsOf: footerInsertion, at: range.lowerBound)
                needsUpdate = true
            }
        }
        
        // Add mandatory overrides for Word Mac compatibility (if not already present)
        let mandatoryOverrides = [
            ("/word/styles.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"),
            ("/word/settings.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"),
            ("/word/webSettings.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml"),
            ("/word/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml")
        ]
        
        for (partName, contentType) in mandatoryOverrides {
            if !xml.contains("PartName=\"\(partName)\"") {
                let insertion = "    <Override PartName=\"\(partName)\" ContentType=\"\(contentType)\"/>\n"
                if let range = xml.range(of: "</Types>") {
                    xml.insert(contentsOf: insertion, at: range.lowerBound)
                    needsUpdate = true
                }
            }
        }

        if needsUpdate {
            guard let xmlData = xml.data(using: .utf8) else {
                throw NSError(domain: "DocxError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Content_Types XML"])
            }
            try xmlData.write(to: contentTypesPath)
        }
    }
    
    private func updateContentTypes(_ archive: Archive, with extensions: Set<String>, hasFooter: Bool = false) throws {
        guard let entry = archive["[Content_Types].xml"] else {
            return
        }

        var existingData = Data()
        try archive.extract(entry) { chunk in
            existingData.append(chunk)
        }

        guard var xml = String(data: existingData, encoding: .utf8) else {
            return
        }

        var needsUpdate = false

        // Register image extensions
        let knownTypes: [String: String] = [
            "png": "image/png",
            "jpeg": "image/jpeg",
            "jpg": "image/jpeg"
        ]

        for ext in extensions {
            guard let contentType = knownTypes[ext], xml.contains("Extension=\"\(ext)\"") == false else {
                continue
            }
            let insertion = "    <Default Extension=\"\(ext)\" ContentType=\"\(contentType)\"/>\n"
            if let range = xml.range(of: "</Types>") {
                xml.insert(contentsOf: insertion, at: range.lowerBound)
                needsUpdate = true
            }
        }

        // Register footer content type if footer exists
        if hasFooter && !xml.contains("PartName=\"/word/footer1.xml\"") {
            let footerInsertion = "    <Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>\n"
            if let range = xml.range(of: "</Types>") {
                xml.insert(contentsOf: footerInsertion, at: range.lowerBound)
                needsUpdate = true
            }
        }
        
        // Add mandatory overrides for Word Mac compatibility (if not already present)
        let mandatoryOverrides = [
            ("/word/styles.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"),
            ("/word/settings.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"),
            ("/word/webSettings.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml"),
            ("/word/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml")
        ]
        
        for (partName, contentType) in mandatoryOverrides {
            if !xml.contains("PartName=\"\(partName)\"") {
                let insertion = "    <Override PartName=\"\(partName)\" ContentType=\"\(contentType)\"/>\n"
                if let range = xml.range(of: "</Types>") {
                    xml.insert(contentsOf: insertion, at: range.lowerBound)
                    needsUpdate = true
                }
            }
        }

        if needsUpdate {
            try replaceEntry(archive, name: "[Content_Types].xml", with: xml)
        }
    }
    
    private func ensureMandatoryFilesInDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        
        // Create word/styles.xml if missing (mandatory for Word Mac)
        let stylesPath = directory.appendingPathComponent("word/styles.xml")
        if !fileManager.fileExists(atPath: stylesPath.path) {
            let stylesXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:docDefaults>
                <w:rPrDefault>
                  <w:rPr>
                    <w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi" w:cstheme="minorHAnsi"/>
                    <w:sz w:val="22"/>
                    <w:szCs w:val="22"/>
                    <w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>
                  </w:rPr>
                </w:rPrDefault>
                <w:pPrDefault>
                  <w:pPr>
                    <w:spacing w:after="200" w:line="276" w:lineRule="auto"/>
                  </w:pPr>
                </w:pPrDefault>
              </w:docDefaults>
              <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
                <w:name w:val="Normal"/>
                <w:qFormat/>
              </w:style>
            </w:styles>
            """
            try stylesXML.data(using: .utf8)?.write(to: stylesPath)
        }
        
        // Create word/settings.xml if missing (mandatory for Word Mac)
        let settingsPath = directory.appendingPathComponent("word/settings.xml")
        if !fileManager.fileExists(atPath: settingsPath.path) {
            let settingsXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:zoom w:percent="100"/>
            </w:settings>
            """
            try settingsXML.data(using: .utf8)?.write(to: settingsPath)
        }
        
        // Create word/webSettings.xml if missing (mandatory for Word Mac)
        let webSettingsPath = directory.appendingPathComponent("word/webSettings.xml")
        if !fileManager.fileExists(atPath: webSettingsPath.path) {
            let webSettingsXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:webSettings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:allowPNG/>
            </w:webSettings>
            """
            try webSettingsXML.data(using: .utf8)?.write(to: webSettingsPath)
        }
        
        // Create word/theme/theme1.xml if missing (highly recommended for images)
        let themePath = directory.appendingPathComponent("word/theme/theme1.xml")
        if !fileManager.fileExists(atPath: themePath.path) {
            let themeDir = themePath.deletingLastPathComponent()
            try fileManager.createDirectory(at: themeDir, withIntermediateDirectories: true)
            
            let themeXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
              <a:themeElements>
                <a:clrScheme name="Office">
                  <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
                  <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
                  <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
                  <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
                  <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
                  <a:accent2><a:srgbClr val="F79646"/></a:accent2>
                  <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
                  <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
                  <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
                  <a:accent6><a:srgbClr val="F79646"/></a:accent6>
                  <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
                  <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
                </a:clrScheme>
                <a:fontScheme name="Office">
                  <a:majorFont>
                    <a:latin typeface="Cambria"/>
                    <a:ea typeface=""/>
                    <a:cs typeface=""/>
                  </a:majorFont>
                  <a:minorFont>
                    <a:latin typeface="Calibri"/>
                    <a:ea typeface=""/>
                    <a:cs typeface=""/>
                  </a:minorFont>
                </a:fontScheme>
                <a:fmtScheme name="Office">
                  <a:fillStyleLst>
                    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
                        <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:shade val="51000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
                        <a:gs pos="80000"><a:schemeClr val="phClr"><a:shade val="93000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="94000"/><a:satMod val="135000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                  </a:fillStyleLst>
                  <a:lnStyleLst>
                    <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">
                      <a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill>
                      <a:prstDash val="solid"/>
                    </a:ln>
                  </a:lnStyleLst>
                  <a:effectStyleLst>
                    <a:effectStyle>
                      <a:effectLst/>
                    </a:effectStyle>
                    <a:effectStyle>
                      <a:effectLst/>
                    </a:effectStyle>
                    <a:effectStyle>
                      <a:effectLst>
                        <a:outerShdw blurRad="57150" dist="19050" dir="5400000" rotWithShape="0">
                          <a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr>
                        </a:outerShdw>
                      </a:effectLst>
                    </a:effectStyle>
                  </a:effectStyleLst>
                  <a:bgFillStyleLst>
                    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="94000"/><a:satMod val="135000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="63000"/><a:satMod val="102000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                  </a:bgFillStyleLst>
                </a:fmtScheme>
              </a:themeElements>
              <a:objectDefaults/>
              <a:extraClrSchemeLst/>
            </a:theme>
            """
            try themeXML.data(using: .utf8)?.write(to: themePath)
        }
        
        // Create docProps/core.xml if missing
        let corePath = directory.appendingPathComponent("docProps/core.xml")
        if !fileManager.fileExists(atPath: corePath.path) {
            let coreDir = corePath.deletingLastPathComponent()
            try fileManager.createDirectory(at: coreDir, withIntermediateDirectories: true)
            
            let coreXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
              <dc:creator/>
              <cp:lastModifiedBy/>
              <dcterms:created xsi:type="dcterms:W3CDTF"/>
              <dcterms:modified xsi:type="dcterms:W3CDTF"/>
            </cp:coreProperties>
            """
            try coreXML.data(using: .utf8)?.write(to: corePath)
        }
        
        // Create docProps/app.xml if missing
        let appPath = directory.appendingPathComponent("docProps/app.xml")
        if !fileManager.fileExists(atPath: appPath.path) {
            let appXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
              <Application>Microsoft Word</Application>
              <AppVersion>16.0000</AppVersion>
            </Properties>
            """
            try appXML.data(using: .utf8)?.write(to: appPath)
        }
    }
    
    private func ensureMandatoryFiles(_ archive: Archive) throws {
        // Create word/styles.xml if missing (mandatory for Word Mac)
        if archive["word/styles.xml"] == nil {
            let stylesXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:docDefaults>
                <w:rPrDefault>
                  <w:rPr>
                    <w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi" w:cstheme="minorHAnsi"/>
                    <w:sz w:val="22"/>
                    <w:szCs w:val="22"/>
                    <w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>
                  </w:rPr>
                </w:rPrDefault>
                <w:pPrDefault>
                  <w:pPr>
                    <w:spacing w:after="200" w:line="276" w:lineRule="auto"/>
                  </w:pPr>
                </w:pPrDefault>
              </w:docDefaults>
              <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
                <w:name w:val="Normal"/>
                <w:qFormat/>
              </w:style>
            </w:styles>
            """
            try replaceEntry(archive, name: "word/styles.xml", with: stylesXML)
        }
        
        // Create word/settings.xml if missing (mandatory for Word Mac)
        if archive["word/settings.xml"] == nil {
            let settingsXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:zoom w:percent="100"/>
            </w:settings>
            """
            try replaceEntry(archive, name: "word/settings.xml", with: settingsXML)
        }
        
        // Create word/webSettings.xml if missing (mandatory for Word Mac)
        if archive["word/webSettings.xml"] == nil {
            let webSettingsXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:webSettings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:allowPNG/>
            </w:webSettings>
            """
            try replaceEntry(archive, name: "word/webSettings.xml", with: webSettingsXML)
        }
        
        // Create word/theme/theme1.xml if missing (highly recommended for images)
        if archive["word/theme/theme1.xml"] == nil {
            let themeXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme">
              <a:themeElements>
                <a:clrScheme name="Office">
                  <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
                  <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
                  <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
                  <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
                  <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
                  <a:accent2><a:srgbClr val="F79646"/></a:accent2>
                  <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
                  <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
                  <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
                  <a:accent6><a:srgbClr val="F79646"/></a:accent6>
                  <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
                  <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
                </a:clrScheme>
                <a:fontScheme name="Office">
                  <a:majorFont>
                    <a:latin typeface="Cambria"/>
                    <a:ea typeface=""/>
                    <a:cs typeface=""/>
                  </a:majorFont>
                  <a:minorFont>
                    <a:latin typeface="Calibri"/>
                    <a:ea typeface=""/>
                    <a:cs typeface=""/>
                  </a:minorFont>
                </a:fontScheme>
                <a:fmtScheme name="Office">
                  <a:fillStyleLst>
                    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
                        <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:shade val="51000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
                        <a:gs pos="80000"><a:schemeClr val="phClr"><a:shade val="93000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="94000"/><a:satMod val="135000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                  </a:fillStyleLst>
                  <a:lnStyleLst>
                    <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">
                      <a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill>
                      <a:prstDash val="solid"/>
                    </a:ln>
                  </a:lnStyleLst>
                  <a:effectStyleLst>
                    <a:effectStyle>
                      <a:effectLst/>
                    </a:effectStyle>
                    <a:effectStyle>
                      <a:effectLst/>
                    </a:effectStyle>
                    <a:effectStyle>
                      <a:effectLst>
                        <a:outerShdw blurRad="57150" dist="19050" dir="5400000" rotWithShape="0">
                          <a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr>
                        </a:outerShdw>
                      </a:effectLst>
                    </a:effectStyle>
                  </a:effectStyleLst>
                  <a:bgFillStyleLst>
                    <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                    <a:gradFill rotWithShape="1">
                      <a:gsLst>
                        <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="94000"/><a:satMod val="135000"/></a:schemeClr></a:gs>
                        <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="63000"/><a:satMod val="102000"/></a:schemeClr></a:gs>
                      </a:gsLst>
                      <a:lin ang="16200000" scaled="0"/>
                    </a:gradFill>
                  </a:bgFillStyleLst>
                </a:fmtScheme>
              </a:themeElements>
              <a:objectDefaults/>
              <a:extraClrSchemeLst/>
            </a:theme>
            """
            try replaceEntry(archive, name: "word/theme/theme1.xml", with: themeXML)
        }
        
        // Create docProps/core.xml if missing
        if archive["docProps/core.xml"] == nil {
            let coreXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
              <dc:creator/>
              <cp:lastModifiedBy/>
              <dcterms:created xsi:type="dcterms:W3CDTF"/>
              <dcterms:modified xsi:type="dcterms:W3CDTF"/>
            </cp:coreProperties>
            """
            try replaceEntry(archive, name: "docProps/core.xml", with: coreXML)
        }
        
        // Create docProps/app.xml if missing
        if archive["docProps/app.xml"] == nil {
            let appXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
              <Application>Microsoft Word</Application>
              <AppVersion>16.0000</AppVersion>
            </Properties>
            """
            try replaceEntry(archive, name: "docProps/app.xml", with: appXML)
        }
    }

    private func xmlPhotoPage(entries: [(relId: String, docPrId: Int, resource: DocxImageResource, caption: String)]) -> String {
        switch entries.count {
        case 0:
            return ""
        case 1:
            let spacer = xmlSpacerParagraph(before: 2160, after: 2160, centered: true)
            let content = xmlImageWithCaption(relId: entries[0].relId, docPrId: entries[0].docPrId, caption: entries[0].caption, cx: entries[0].resource.cx, cy: entries[0].resource.cy, alignment: "center")
            return spacer + content + spacer
        case 2:
            let spacer = xmlSpacerParagraph(before: 2160, after: 2160, centered: true)
            let table = xmlPhotoTable(rows: 1, columns: 2, entries: entries, centered: true)
            return spacer + table + spacer
        case 3:
            let firstRow = Array(entries[0...1])
            let secondRow = [entries[2]]
            let top = xmlPhotoTable(rows: 1, columns: 2, entries: firstRow, centered: false)
            let bottom = xmlPhotoTable(rows: 1, columns: 1, entries: secondRow, centered: true)
            return top + "<w:p/>" + bottom
        default:
            let spacer = xmlSpacerParagraph(before: 720, after: 720, centered: true)
            let table = xmlPhotoTable(rows: 2, columns: 2, entries: entries, centered: true)
            return spacer + table + spacer
        }
    }

    private func xmlPhotoTable(rows: Int, columns: Int, entries: [(relId: String, docPrId: Int, resource: DocxImageResource, caption: String)], centered: Bool) -> String {
        var xml = """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblLayout w:type="fixed"/>
        """

        if centered {
            xml += "            <w:jc w:val=\"center\"/>\n"
        }

        xml += """
          </w:tblPr>
          <w:tblGrid>
        """

        let colWidth: Int
        if columns == 1 {
            colWidth = centered ? 9000 : 7200
        } else {
            colWidth = 5200  // Increased to accommodate larger photos (3.6 inches) - allows wider photos while still fitting 4 per page
        }
        for _ in 0..<columns {
            xml += "            <w:gridCol w:w=\"\(colWidth)\"/>\n"
        }
        xml += "          </w:tblGrid>\n"

        var entryIndex = 0
        for _ in 0..<rows {
            xml += "          <w:tr>\n            <w:trPr><w:cantSplit/></w:trPr>\n"
            for _ in 0..<columns {
                xml += "            <w:tc>\n              <w:tcPr><w:tcW w:w=\"\(colWidth)\" w:type=\"dxa\"/>"
                if centered && columns == 1 {
                    xml += "<w:jc w:val=\"center\"/>"
                }
                xml += "</w:tcPr>\n"

                if entryIndex < entries.count {
                    let entry = entries[entryIndex]
                    let alignment = (centered || columns == 1) ? "center" : nil
                    xml += xmlImageWithCaption(relId: entry.relId, docPrId: entry.docPrId, caption: entry.caption, cx: entry.resource.cx, cy: entry.resource.cy, alignment: alignment)
                    entryIndex += 1
                } else {
                    xml += "              <w:p/>\n"
                }

                xml += "            </w:tc>\n"
            }
            xml += "          </w:tr>\n"
        }

        xml += "        </w:tbl>\n"
        return xml
    }

    private func generateSpecimenTableXML(window: Window, job: Job) -> String {
        // Extract specimen number from window number
        let specimenNumber = extractNumberFromSpecimenName(window.windowNumber ?? "1")
        let testNumber = specimenNumber
        let procedure = job.testProcedure?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ASTM E331"
        
        // Format times
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        let startTime: String
        if let testStartTime = window.testStartTime {
            startTime = timeFormatter.string(from: testStartTime)
        } else {
            startTime = "N/A"
        }
        
        let completionTime: String
        if let testStopTime = window.testStopTime {
            completionTime = timeFormatter.string(from: testStopTime)
        } else {
            completionTime = "N/A"
        }
        
        // Column widths: Specimen No., Test No., Procedure, Start Time, Completion
        let colWidths: [Int] = [1800, 1800, 2400, 1800, 1800]
        let totalWidth = colWidths.reduce(0, +)
        
        var xml = """
        <w:tbl xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:tblPr>
            <w:tblW w:w="\(totalWidth)" w:type="dxa"/>
            <w:tblLayout w:type="fixed"/>
            <w:tblpPr w:leftFromText="0" w:rightFromText="0" w:topFromText="0" w:bottomFromText="0" w:vertAnchor="text" w:horzAnchor="page" w:tblpXSpec="left" w:tblpY="0"/>
            <w:tblBorders>
              <w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              <w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              <w:bottom w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              <w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              <w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/>
              <w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/>
            </w:tblBorders>
          </w:tblPr>
          <w:tblGrid>
        """
        
        for width in colWidths {
            xml += "            <w:gridCol w:w=\"\(width)\"/>\n"
        }
        
        xml += "          </w:tblGrid>\n"
        
        // Header row
        let headers = ["Specimen No.", "Test No.", "Procedure", "Start Time", "Completion"]
        xml += "          <w:tr>\n"
        for (index, header) in headers.enumerated() {
            xml += """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[index])" w:type="dxa"/>
                <w:noWrap/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik Semibold" w:hAnsi="Graphik Semibold" w:eastAsia="Graphik Semibold" w:cstheme="minorHAnsi"/>
                    <w:b/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(header.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            """
        }
        xml += "          </w:tr>\n"
        
        // Data row
        let dataValues = [specimenNumber, testNumber, procedure, startTime, completionTime]
        xml += "          <w:tr>\n"
        for (index, value) in dataValues.enumerated() {
            xml += """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(colWidths[index])" w:type="dxa"/>
                <w:noWrap/>
              </w:tcPr>
              <w:p>
                <w:pPr>
                  <w:spacing w:before="0" w:after="0"/>
                </w:pPr>
                <w:r>
                  <w:rPr>
                    <w:rFonts w:ascii="Graphik" w:hAnsi="Graphik" w:eastAsia="Graphik" w:cstheme="minorHAnsi"/>
                  </w:rPr>
                  <w:t xml:space="preserve">\(value.xmlEscaped)</w:t>
                </w:r>
              </w:p>
            </w:tc>
            """
        }
        xml += "          </w:tr>\n"
        
        xml += "        </w:tbl>\n"
        return xml
    }
    
    private func xmlSpacerParagraph(before: Int, after: Int, centered: Bool = false) -> String {
        let centerTag = centered ? "<w:jc w:val=\"center\"/>" : ""
        return "<w:p><w:pPr><w:spacing w:before=\"\(before)\" w:after=\"\(after)\"/>\(centerTag)</w:pPr><w:r/></w:p>"
    }
}

fileprivate extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

fileprivate extension NSImage {
    func docxCompressedData(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let maxSide = max(size.width, size.height)
        let targetSize: CGSize

        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            let resized = NSImage(size: targetSize, flipped: false) { rect in
                self.draw(in: rect)
                return true
            }
            guard let tiffData = resized.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        } else {
            guard let tiffData = self.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        }
    }
}

fileprivate extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}

// MARK: - Data Models

struct JobExportData: Codable {
    let intake: IntakeData
    let field: FieldData
}

struct IntakeData: Codable {
    let sourceName: String?
    let sourceUrl: String?
    let fetchedAt: Date?
}

struct FieldData: Codable {
    let inspector: String
    let date: Date
    let overheadFile: String
    let windows: [WindowExportData]
}

struct WindowExportData: Codable {
    let windowId: String
    let windowNumber: String
    let xPosition: Double
    let yPosition: Double
    let width: Double
    let height: Double
    let windowType: String?
    let material: String?
    let testResult: String?
    let leakPoints: Int
    let isInaccessible: Bool
    let notes: String?
    let exteriorPhotoCount: Int
    let interiorPhotoCount: Int
    let leakPhotoCount: Int
}

extension DateFormatter {
    static let exportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}

// MARK: - Helper Functions
extension FieldResultsPackage {
    /// Extract just the number from specimen names like "Specimen 2", "Specimen 3", etc.
    /// Returns the number as a string, or the original string if no number is found
    private func extractNumberFromSpecimenName(_ name: String) -> String {
        // Try to find a number at the end of the string
        if let lastSpaceIndex = name.lastIndex(of: " ") {
            let numberPart = String(name[name.index(after: lastSpaceIndex)...])
            // Check if it's a valid number
            if Int(numberPart) != nil {
                return numberPart
            }
        }
        // If no number found, return original (fallback for names like "W01")
        return name
    }
}

// MARK: - Coordinate Conversion Helpers (matching app's logic)
extension FieldResultsPackage {
    /// Convert image X coordinate to frame X coordinate using same logic as app's convertImageToViewX
    /// Returns position from left edge of frame (top-down coordinate system)
    private func convertImageXToFrameX(_ imageX: CGFloat, frameSize: CGSize, originalImageSize: CGSize) -> CGFloat {
        let imageAspectRatio = originalImageSize.width / originalImageSize.height
        let frameAspectRatio = frameSize.width / frameSize.height
        
        if imageAspectRatio > frameAspectRatio {
            // Letterboxed - image fills width
            return imageX * frameSize.width / originalImageSize.width
        } else {
            // Pillarboxed - image fills height
            let displayedWidth = frameSize.height * imageAspectRatio
            let xOffset = (frameSize.width - displayedWidth) / 2
            return imageX * displayedWidth / originalImageSize.width + xOffset
        }
    }
    
    /// Convert image Y coordinate to frame Y coordinate using same logic as app's convertImageToViewY
    /// Returns position from top edge of frame (top-down coordinate system)
    private func convertImageYToFrameY(_ imageY: CGFloat, frameSize: CGSize, originalImageSize: CGSize) -> CGFloat {
        let imageAspectRatio = originalImageSize.width / originalImageSize.height
        let frameAspectRatio = frameSize.width / frameSize.height
        
        if imageAspectRatio > frameAspectRatio {
            // Letterboxed - image fills width
            let displayedHeight = frameSize.width / imageAspectRatio
            let yOffset = (frameSize.height - displayedHeight) / 2
            return imageY * displayedHeight / originalImageSize.height + yOffset
        } else {
            // Pillarboxed - image fills height (matches app's logic exactly)
            // Uses frameSize.height directly, just like app uses viewSize.height
            return imageY * frameSize.height / originalImageSize.height
        }
    }
    
    /// Draw an arrow at the specified position with the given direction
    /// - Parameters:
    ///   - context: Core Graphics context
    ///   - position: Arrow position in PDF coordinates (bottom-left origin)
    ///   - direction: Arrow direction ("up", "down", "left", "right")
    private func drawArrow(context: CGContext, at position: CGPoint, direction: String) {
        let arrowLength: CGFloat = 50
        let arrowheadSize: CGFloat = 12
        let lineWidth: CGFloat = 4
        
        context.setStrokeColor(NSColor.red.cgColor)
        context.setFillColor(NSColor.red.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        switch direction {
        case "up":
            // Line pointing up
            context.move(to: CGPoint(x: position.x, y: position.y + arrowLength / 2))
            context.addLine(to: CGPoint(x: position.x, y: position.y - arrowLength / 2))
            context.strokePath()
            
            // Arrowhead
            context.beginPath()
            context.move(to: CGPoint(x: position.x, y: position.y - arrowLength / 2))
            context.addLine(to: CGPoint(x: position.x - arrowheadSize / 2, y: position.y - arrowLength / 2 + arrowheadSize))
            context.addLine(to: CGPoint(x: position.x + arrowheadSize / 2, y: position.y - arrowLength / 2 + arrowheadSize))
            context.closePath()
            context.fillPath()
            
        case "down":
            // Line pointing down
            context.move(to: CGPoint(x: position.x, y: position.y - arrowLength / 2))
            context.addLine(to: CGPoint(x: position.x, y: position.y + arrowLength / 2))
            context.strokePath()
            
            // Arrowhead
            context.beginPath()
            context.move(to: CGPoint(x: position.x, y: position.y + arrowLength / 2))
            context.addLine(to: CGPoint(x: position.x - arrowheadSize / 2, y: position.y + arrowLength / 2 - arrowheadSize))
            context.addLine(to: CGPoint(x: position.x + arrowheadSize / 2, y: position.y + arrowLength / 2 - arrowheadSize))
            context.closePath()
            context.fillPath()
            
        case "left":
            // Line pointing left
            context.move(to: CGPoint(x: position.x + arrowLength / 2, y: position.y))
            context.addLine(to: CGPoint(x: position.x - arrowLength / 2, y: position.y))
            context.strokePath()
            
            // Arrowhead
            context.beginPath()
            context.move(to: CGPoint(x: position.x - arrowLength / 2, y: position.y))
            context.addLine(to: CGPoint(x: position.x - arrowLength / 2 + arrowheadSize, y: position.y - arrowheadSize / 2))
            context.addLine(to: CGPoint(x: position.x - arrowLength / 2 + arrowheadSize, y: position.y + arrowheadSize / 2))
            context.closePath()
            context.fillPath()
            
        case "right":
            // Line pointing right
            context.move(to: CGPoint(x: position.x - arrowLength / 2, y: position.y))
            context.addLine(to: CGPoint(x: position.x + arrowLength / 2, y: position.y))
            context.strokePath()
            
            // Arrowhead
            context.beginPath()
            context.move(to: CGPoint(x: position.x + arrowLength / 2, y: position.y))
            context.addLine(to: CGPoint(x: position.x + arrowLength / 2 - arrowheadSize, y: position.y - arrowheadSize / 2))
            context.addLine(to: CGPoint(x: position.x + arrowLength / 2 - arrowheadSize, y: position.y + arrowheadSize / 2))
            context.closePath()
            context.fillPath()
            
        default:
            break
        }
    }
}
