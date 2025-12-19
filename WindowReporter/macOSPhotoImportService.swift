//
//  macOSPhotoImportService.swift
//  WindowReporter
//
//  macOS-specific photo import service supporting Photos library and file system
//

import Foundation
import CoreData
import Photos
import AppKit
import UniformTypeIdentifiers

class macOSPhotoImportService {
    private let context: NSManagedObjectContext
    private let documentsDirectory: URL
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // MARK: - Import from Photos Library
    
    func importFromPhotosLibrary(asset: PHAsset, window: Window, photoType: PhotoType, note: String? = nil) async throws -> Photo {
        // Check if photo already exists
        let fetchRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "localIdentifier == %@ AND window == %@ AND photoType == %@", asset.localIdentifier, window, photoType.rawValue)
        fetchRequest.fetchLimit = 1
        
        if let existingPhoto = try? context.fetch(fetchRequest).first {
            // Update existing photo
            existingPhoto.notes = note
            return existingPhoto
        }
        
        // Create new photo entity
        let photo = Photo(context: context)
        photo.photoId = UUID().uuidString
        photo.photoType = photoType.rawValue
        photo.localIdentifier = asset.localIdentifier
        photo.photoSource = "PhotosLibrary"
        photo.createdAt = Date()
        photo.notes = note
        photo.includeInReport = true
        photo.window = window
        
        print("MYDEBUG → macOSPhotoImportService - Creating photo: ID=\(photo.photoId ?? "nil"), Type=\(photoType.rawValue), Window=\(window.windowNumber ?? "nil")")
        
        try context.save()
        
        print("MYDEBUG → macOSPhotoImportService - Photo saved successfully. Window now has \(window.photos?.count ?? 0) photos")
        
        return photo
    }
    
    // MARK: - Import from File System
    
    func importFromFile(url: URL, window: Window, photoType: PhotoType, note: String? = nil) async throws -> Photo {
        // Ensure window has a job
        guard window.job != nil else {
            throw NSError(domain: "PhotoImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Window must have a job"])
        }
        // Copy file to app's photos directory
        let copiedURL = try await copyPhotoToAppDirectory(from: url, window: window)
        
        // Create relative path
        let relativePath = "photos/\(window.job?.jobId ?? "unknown")/\(window.windowId ?? "unknown")/\(copiedURL.lastPathComponent)"
        
        // Check if photo already exists
        let fetchRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "filePath == %@ AND window == %@ AND photoType == %@", relativePath, window, photoType.rawValue)
        fetchRequest.fetchLimit = 1
        
        if let existingPhoto = try? context.fetch(fetchRequest).first {
            // Update existing photo
            existingPhoto.notes = note
            return existingPhoto
        }
        
        // Create new photo entity
        let photo = Photo(context: context)
        let photoIdBefore = photo.photoId
        photo.photoId = UUID().uuidString
        photo.photoType = photoType.rawValue
        photo.filePath = relativePath
        photo.photoSource = "FileSystem"
        photo.createdAt = Date()
        photo.notes = note
        photo.includeInReport = true
        
        // Log before setting relationship
        let photosBefore = window.photos?.count ?? 0
        print("MYDEBUG → macOSPhotoImportService - Creating photo from file:")
        print("MYDEBUG →   Photo ID: \(photo.photoId ?? "nil")")
        print("MYDEBUG →   Photo Type: \(photoType.rawValue)")
        print("MYDEBUG →   Window ID: \(window.windowId ?? "nil")")
        print("MYDEBUG →   Window Number: \(window.windowNumber ?? "nil")")
        print("MYDEBUG →   Window has \(photosBefore) photos before adding new photo")
        print("MYDEBUG →   File Path: \(relativePath)")
        
        // Set window relationship
        photo.window = window
        
        // Refresh window to ensure relationship is visible
        context.refresh(window, mergeChanges: true)
        
        // Log after setting relationship (before save)
        let photosAfterSet = window.photos?.count ?? 0
        print("MYDEBUG →   Window has \(photosAfterSet) photos after setting relationship (before save)")
        
        try context.save()
        
        // Refresh window again after save to ensure relationship is fully established
        context.refresh(window, mergeChanges: true)
        
        // Verify relationship after save
        let photosAfterSave = window.photos?.count ?? 0
        print("MYDEBUG → macOSPhotoImportService - Photo saved successfully")
        print("MYDEBUG →   Window now has \(photosAfterSave) photos after save")
        if let photosSet = window.photos {
            let photoArray = photosSet.allObjects as? [Photo] ?? []
            print("MYDEBUG →   Photo IDs in window.photos:")
            for p in photoArray {
                print("MYDEBUG →     - Photo ID: \(p.photoId ?? "nil"), Type: \(p.photoType ?? "nil")")
            }
        }
        
        return photo
    }
    
    // MARK: - Helper Methods
    
    private func copyPhotoToAppDirectory(from url: URL, window: Window) async throws -> URL {
        // Create photos directory structure: photos/{jobId}/{windowId}/
        let jobId = window.job?.jobId ?? "unknown"
        let windowId = window.windowId ?? "unknown"
        let photosDirectory = documentsDirectory
            .appendingPathComponent("photos")
            .appendingPathComponent(jobId)
            .appendingPathComponent(windowId)
        
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        
        // Generate unique filename
        let fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = photosDirectory.appendingPathComponent(fileName)
        
        // Copy file
        try FileManager.default.copyItem(at: url, to: destinationURL)
        
        return destinationURL
    }
    
    // MARK: - Get Image Data
    
    func getImageData(for photo: Photo) async -> Data? {
        if photo.photoSource == "PhotosLibrary", let localIdentifier = photo.localIdentifier {
            // Fetch from Photos library
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else { return nil }
            
            return await fetchPhotoImageData(asset: asset)
        } else if photo.photoSource == "FileSystem", let filePath = photo.filePath {
            // Load from file system
            let fullPath = documentsDirectory.appendingPathComponent(filePath)
            return try? Data(contentsOf: fullPath)
        }
        
        return nil
    }
    
    func getImage(for photo: Photo) async -> NSImage? {
        guard let imageData = await getImageData(for: photo) else { return nil }
        return NSImage(data: imageData)
    }
    
    private func fetchPhotoImageData(asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, _ in
                continuation.resume(returning: imageData)
            }
        }
    }
}

