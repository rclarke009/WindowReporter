//
//  SettingsView.swift
//  WindowReporter
//
//  macOS settings view
//

import SwiftUI
import AppKit

/// Role for onsite transfer: main user (indoors) vs add-on user (outside). Used to tailor UI.
enum TransferRole: String, CaseIterable {
    case main = "main"
    case addOn = "addOn"
    case both = "both"
    
    var label: String {
        switch self {
        case .main: return "Main user (indoors)"
        case .addOn: return "Add-on user (outside)"
        case .both: return "Both / I switch"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("inspectorName") private var inspectorName: String = ""
    @AppStorage("jobsSortOrder") private var jobsSortOrderRaw: String = JobSortOrder.newestFirst.rawValue
    @AppStorage("transferRole") private var transferRoleRaw: String = TransferRole.both.rawValue
    @AppStorage("timerConflictPreference") private var timerConflictPreferenceRaw: String = "main"
    @AppStorage("defaultEnabledTestingTypeIds") private var defaultEnabledTestingTypeIds: String = "windows"
    @AppStorage("defaultTestingTypeNotes") private var defaultTestingTypeNotes: String = ""
    
    @State private var enabledTestingTypeIds: Set<String> = ["windows"]
    @State private var testingTypeNote: [String: String] = [:]
    @State private var hasConfiguredWindow = false

    private var jobsSortOrder: Binding<JobSortOrder> {
        Binding(
            get: { JobSortOrder(rawValue: jobsSortOrderRaw) ?? .newestFirst },
            set: { jobsSortOrderRaw = $0.rawValue }
        )
    }
    
    private func saveTestingDefaults() {
        defaultEnabledTestingTypeIds = TeamTestingTypesOrdering.commaJoinedPreservingOrder(enabledIds: enabledTestingTypeIds)
        let filtered = testingTypeNote.filter { !($0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        defaultTestingTypeNotes = filtered.isEmpty ? "" : (try? JSONEncoder().encode(filtered)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    Form {
                    Section {
                        Button {
                            NotificationCenter.default.post(name: .backupAllJobsRequested, object: nil)
                        } label: {
                            Label("Backup All Jobs to ZIP", systemImage: "archivebox")
                        }
                        Text("Creates a portable ZIP archive of every job for import into any app version. Jobs are marked Archived after a successful backup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    } header: {
                        Text("Data Backup")
                    }

                    Section("Inspector Information") {
                        TextField("Default Inspector Name", text: $inspectorName)
                            .frame(maxWidth: 420, alignment: .leading)
                    }

                    Section("Jobs List") {
                        Picker("Sort order", selection: jobsSortOrder) {
                            Text("Newest first").tag(JobSortOrder.newestFirst)
                            Text("Alphabetical (A–Z)").tag(JobSortOrder.alphabetical)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section("Onsite transfer") {
                        Picker("I am", selection: $transferRoleRaw) {
                            ForEach(TransferRole.allCases, id: \.rawValue) { role in
                                Text(role.label).tag(role.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Specimen time conflict", selection: $timerConflictPreferenceRaw) {
                            Text("Use my times").tag("main")
                            Text("Use add-on's times").tag("addOn")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section {
                        Text("Default testing types for new jobs. Exported packages send this to the field app. You can also set testing per job by opening a job and choosing Edit Job (pencil next to the address).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    } header: { Text("Testing types") }
                    Section("Types to include by default") {
                        ForEach(TeamTestingTypesOrdering.rowsForToggles(currentSelection: enabledTestingTypeIds, job: nil), id: \.id) { typeItem in
                            let binding = Binding(
                                get: { enabledTestingTypeIds.contains(typeItem.id) },
                                set: { enabled in
                                    if enabled {
                                        enabledTestingTypeIds.insert(typeItem.id)
                                    } else {
                                        enabledTestingTypeIds.remove(typeItem.id)
                                        testingTypeNote.removeValue(forKey: typeItem.id)
                                    }
                                    saveTestingDefaults()
                                }
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(typeItem.name, isOn: binding)
                                if enabledTestingTypeIds.contains(typeItem.id) {
                                    TextField("Note for this type (optional)", text: Binding(
                                        get: { testingTypeNote[typeItem.id] ?? "" },
                                        set: {
                                            testingTypeNote[typeItem.id] = $0.isEmpty ? nil : $0
                                            saveTestingDefaults()
                                        }
                                    ), axis: .vertical)
                                    .lineLimit(1...2)
                                    .font(.subheadline)
                                    .frame(maxWidth: 360, alignment: .leading)
                                }
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            AuthGateView {
                                CustomizationsHubView()
                            }
                        } label: {
                            Label("Team customizations", systemImage: "slider.horizontal.3")
                        }
                        Text("Cloud team settings (same account as WTestBeta). Photo categories, testing types, type lists per testing procedure, report text, and procedures.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    } header: {
                        Text("Team")
                    } footer: {
                        Text("The section below is for local / file-based photo note categories to embed in exported packages, separate from cloud team data.")
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    }

                    Section {
                        NavigationLink("Photo note categories (local file)") {
                            PhotoNoteCategoriesEditorView()
                        }
                        Text("Categories and caption options for package files. The field app uses team cloud customizations when signed in, or this data from full job packages.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                            .padding(.bottom, 8)
                    } header: {
                        Text("Field app package / local")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 8)
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
                    .formStyle(.grouped)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                Divider()
                HStack(spacing: 12) {
                    Button("Save") {
                        saveTestingDefaults()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 90)

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                let raw = defaultEnabledTestingTypeIds.trimmingCharacters(in: .whitespacesAndNewlines)
                enabledTestingTypeIds = raw.isEmpty ? ["windows"] : Set(raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                if let data = defaultTestingTypeNotes.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    testingTypeNote = decoded
                } else {
                    testingTypeNote = [:]
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 820, minHeight: 560, idealHeight: 760)
        .background(
            SettingsWindowAccessor { window in
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                configureSettingsWindow(window)
            }
        )
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.contentMinSize = NSSize(width: 640, height: 560)
        keepWindowOnScreen(window)
    }

    private func keepWindowOnScreen(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }

        var frame = window.frame

        // Clamp size so the frame can always fit the visible area.
        frame.size.width = min(frame.size.width, visibleFrame.width)
        frame.size.height = min(frame.size.height, visibleFrame.height)

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.size.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.size.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        window.setFrame(frame, display: true)
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindowReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowReady(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowReady(window)
            }
        }
    }
}

#Preview {
    SettingsView()
}
