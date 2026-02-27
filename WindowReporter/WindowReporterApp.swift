//
//  WindowReporterApp.swift
//  WindowReporter
//
//  Created by Rebecca Clarke on 11/18/25.
//

import SwiftUI
import AppKit

@main
struct WindowReporterApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Ensure signature images are available in Documents directory
        ensureSignatureImagesAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job") {
                    NotificationCenter.default.post(name: .createNewJob, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
    
    private func ensureSignatureImagesAvailable() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        
        // Create images directory if it doesn't exist
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        let signatureImages = ["TrueLogoDark.png", "TrueLogoEmailLight.jpg"]
        
        for imageName in signatureImages {
            let destURL = imagesDirectory.appendingPathComponent(imageName)
            
            // Skip if already exists
            if FileManager.default.fileExists(atPath: destURL.path) {
                continue
            }
            
            // Try to copy from bundle
            let resourceName = imageName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "")
            let resourceType = imageName.hasSuffix(".png") ? "png" : "jpg"
            
            if let bundlePath = Bundle.main.path(forResource: resourceName, ofType: resourceType, inDirectory: "images") {
                do {
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: destURL)
                    print("MYDEBUG →", "Copied \(imageName) from bundle to Documents")
                    continue
                } catch {
                    print("MYDEBUG →", "Failed to copy \(imageName) from bundle: \(error.localizedDescription)")
                }
            }
            
            // Try to load via NSImage and save
            if let image = NSImage(named: resourceName) ?? NSImage(named: "images/\(resourceName)") {
                if let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData) {
                    let imageData: Data?
                    if resourceType == "png" {
                        imageData = bitmapRep.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    }
                    
                    if let data = imageData {
                        do {
                            try data.write(to: destURL)
                            print("MYDEBUG →", "Saved \(imageName) to Documents from NSImage")
                            continue
                        } catch {
                            print("MYDEBUG →", "Failed to save \(imageName) to Documents: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
