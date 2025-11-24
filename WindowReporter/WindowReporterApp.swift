//
//  WindowReporterApp.swift
//  WindowReporter
//
//  Created by Rebecca Clarke on 11/18/25.
//

import SwiftUI

@main
struct WindowReporterApp: App {
    let persistenceController = PersistenceController.shared

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
}

extension Notification.Name {
    static let createNewJob = Notification.Name("createNewJob")
    static let newJobCreated = Notification.Name("newJobCreated")
    static let jobDataUpdated = Notification.Name("jobDataUpdated")
}
