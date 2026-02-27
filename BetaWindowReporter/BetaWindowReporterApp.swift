//
//  BetaWindowReporterApp.swift
//  BetaWindowReporter
//
//  Created by Rebecca Clarke on 2/26/26.
//

import SwiftUI
import CoreData

@main
struct BetaWindowReporterApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
