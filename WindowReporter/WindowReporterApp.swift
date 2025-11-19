//
//  WindowReporterApp.swift
//  WindowReporter
//
//  Created by Rebecca Clarke on 11/18/25.
//

import SwiftUI

@main
struct WindowReporterApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: WindowReporterDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
