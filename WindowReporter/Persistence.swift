//
//  Persistence.swift
//  WindowReporter
//
//  Created for macOS ReportWriter app
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample jobs for preview
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
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

