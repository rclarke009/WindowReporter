//
//  Persistence.swift
//  WindowReporter
//
//  Created for macOS ReportWriter app
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    /// Set when the persistent store fails to load (migration error, disk full, etc.).
    private(set) var loadError: NSError?

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        let sampleJob1 = Job(context: viewContext)
        sampleJob1.jobId = "E2025-05091"
        sampleJob1.clientName = "Smith"
        sampleJob1.addressLine1 = "408 2nd Ave NW"
        sampleJob1.city = "Largo"
        sampleJob1.state = "FL"
        sampleJob1.zip = "33770"
        sampleJob1.status = "Ready"
        sampleJob1.createdAt = Date()
        sampleJob1.updatedAt = Date()
        
        let sampleJob2 = Job(context: viewContext)
        sampleJob2.jobId = "E2025-05092"
        sampleJob2.clientName = "Johnson"
        sampleJob2.addressLine1 = "1121 Palm Dr"
        sampleJob2.city = "Clearwater"
        sampleJob2.state = "FL"
        sampleJob2.zip = "33755"
        sampleJob2.status = "In Progress"
        sampleJob2.createdAt = Date()
        sampleJob2.updatedAt = Date()
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "WindowReporter")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        var capturedLoadError: NSError?
        let container = self.container
        container.loadPersistentStores(completionHandler: { (_, error) in
            if let error = error as NSError? {
                print("MYDEBUG →", "Core Data store load failed:", error, error.userInfo)
                capturedLoadError = error
            } else {
                Self.migrateLegacyPhotoFields(context: container.viewContext)
            }
        })
        self.loadError = capturedLoadError
        self.container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Backfill photoSource on photos migrated from older schema versions.
    static func migrateLegacyPhotoFields(context: NSManagedObjectContext) {
        var didChange = false

        let photoRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        photoRequest.predicate = NSPredicate(format: "photoSource == nil OR photoSource == ''")
        if let photos = try? context.fetch(photoRequest) {
            for photo in photos {
                photo.photoSource = inferredPhotoSource(
                    localIdentifier: photo.localIdentifier,
                    filePath: photo.filePath
                )
                didChange = true
            }
            if !photos.isEmpty {
                print("MYDEBUG → Backfilled photoSource for \(photos.count) Photo row(s)")
            }
        }

        let sectionPhotoRequest: NSFetchRequest<SectionPhoto> = SectionPhoto.fetchRequest()
        sectionPhotoRequest.predicate = NSPredicate(format: "photoSource == nil OR photoSource == ''")
        if let sectionPhotos = try? context.fetch(sectionPhotoRequest) {
            for photo in sectionPhotos {
                photo.photoSource = inferredPhotoSource(
                    localIdentifier: photo.localIdentifier,
                    filePath: photo.filePath
                )
                didChange = true
            }
            if !sectionPhotos.isEmpty {
                print("MYDEBUG → Backfilled photoSource for \(sectionPhotos.count) SectionPhoto row(s)")
            }
        }

        if didChange {
            do {
                try context.save()
            } catch {
                print("MYDEBUG → Error saving legacy photo field migration: \(error.localizedDescription)")
            }
        }
    }

    static func inferredPhotoSource(localIdentifier: String?, filePath: String?) -> String {
        let trimmedID = localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedID.isEmpty {
            return "PhotosLibrary"
        }
        let trimmedPath = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPath.isEmpty {
            return "FileSystem"
        }
        return "PhotosLibrary"
    }
}
