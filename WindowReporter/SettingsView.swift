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
    @AppStorage("jobsSortOrder") private var jobsSortOrderRaw: String = JobSortOrder.newestFirst.rawValue

    private var jobsSortOrder: Binding<JobSortOrder> {
        Binding(
            get: { JobSortOrder(rawValue: jobsSortOrderRaw) ?? .newestFirst },
            set: { jobsSortOrderRaw = $0.rawValue }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Inspector Information") {
                    TextField("Default Inspector Name", text: $inspectorName)
                }

                Section("Jobs List") {
                    Picker("Sort order", selection: jobsSortOrder) {
                        Text("Newest first").tag(JobSortOrder.newestFirst)
                        Text("Alphabetical (A–Z)").tag(JobSortOrder.alphabetical)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("About") {
                    Text("WindowReporter")
                        .font(.headline)
                    Text("macOS Report Writer App")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Version \(appVersion) (\(appBuild))")
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

