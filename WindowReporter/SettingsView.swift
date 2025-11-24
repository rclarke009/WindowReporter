//
//  SettingsView.swift
//  WindowReporter
//
//  macOS settings view
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("inspectorName") private var inspectorName: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Inspector Information") {
                    TextField("Default Inspector Name", text: $inspectorName)
                }
                
                Section("About") {
                    Text("WindowReporter")
                        .font(.headline)
                    Text("macOS Report Writer App")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView()
}

