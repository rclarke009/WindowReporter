//
//  TestingTypesAndProceduresView.swift
//  WindowReporter
//
//  Combined admin editor: testing type list with drill-in for title, active, and procedures.
//

import SwiftUI

struct TestingTypesAndProceduresView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var types: [CachedTestingType] = []
    @State private var configs: [String: CachedProcedureConfig] = [:]
    @State private var isSavingList = false
    @State private var showingAddType = false
    @State private var newTypeId = ""
    @State private var newTypeDisplayName = ""
    @State private var listStatusMessage: String?
    @State private var showCustomTypeDeleteOptions = false
    @State private var typePendingDelete: CachedTestingType?

    var body: some View {
        List {
            Section {
                ForEach(types) { t in
                    NavigationLink {
                        TestingTypeDetailView(
                            typeId: t.id,
                            types: $types,
                            configs: $configs
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.displayName)
                                Text(t.id)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if !t.enabled {
                                Text("Inactive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            let count = configs[t.id]?.steps.count
                                ?? BuiltInTestingProcedureDefaults.defaultConfig(for: t.id).steps.count
                            Text(count > 0 ? "\(count) steps" : "default")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    let builtInIds = Set(TestingTypeId.allCases.map(\.rawValue))
                    for idx in indexSet {
                        guard !builtInIds.contains(types[idx].id) else { continue }
                        typePendingDelete = types[idx]
                        showCustomTypeDeleteOptions = true
                        break
                    }
                }
                .onMove { from, to in types.move(fromOffsets: from, toOffset: to) }
            } footer: {
                #if os(iOS)
                Text("Order is used for default testing types and per-job testing lists. Tap Edit, then drag rows. Open a type to set its title, whether it is active for field users after sync, and its procedure steps. Built-in types can be disabled but not deleted.")
                #else
                Text("Order is used for default testing types and per-job testing lists. Drag rows to reorder. Open a type to set its title, whether it is active for field users after sync, and its procedure steps. Built-in types can be disabled but not deleted.")
                #endif
            }

            Section {
                Button {
                    showingAddType = true
                } label: {
                    Label("Add Custom Type", systemImage: "plus")
                }
            }

            if let listStatusMessage {
                Section {
                    Text(listStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Testing Types and Procedures")
        #if os(macOS)
        .help("Drag rows to set the order used across the app. Open a type to edit its details and procedures.")
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveTypesList() }
                } label: {
                    if isSavingList { ProgressView() } else { Text("Save") }
                }
                .disabled(isSavingList)
            }
        }
        .alert("New Testing Type", isPresented: $showingAddType) {
            TextField("ID (e.g. plumbing)", text: $newTypeId)
            TextField("Display Name", text: $newTypeDisplayName)
            Button("Add") {
                let id = newTypeId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "")
                let name = newTypeDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty else { return }
                types.append(CachedTestingType(id: id, displayName: name, enabled: true))
                newTypeId = ""
                newTypeDisplayName = ""
            }
            Button("Cancel", role: .cancel) { newTypeId = ""; newTypeDisplayName = "" }
        }
        .confirmationDialog("Custom testing type", isPresented: $showCustomTypeDeleteOptions, titleVisibility: .visible) {
            Button("Turn off for new work (recommended)") {
                if let t = typePendingDelete, let i = types.firstIndex(where: { $0.id == t.id }) {
                    types[i].enabled = false
                }
                typePendingDelete = nil
            }
            Button("Remove from team list", role: .destructive) {
                if let t = typePendingDelete {
                    types.removeAll { $0.id == t.id }
                }
                typePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                typePendingDelete = nil
            }
        } message: {
            if let t = typePendingDelete {
                Text("Disabling keeps this type’s id in the team list so WTestBeta and exports can still show “\(t.displayName)” for existing jobs. Removing the row can make labels worse for any job that still references id “\(t.id)” after the team syncs.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let orgId = supabase.organizationId else { return }
        await CustomizationSyncService.syncTestingTypes(organizationId: orgId)
        await CustomizationSyncService.syncTestingProcedures(organizationId: orgId)

        if let cached = TeamCustomizationCache.testingTypes(), !cached.isEmpty {
            types = cached
        } else {
            types = TestingTypeId.allCases.map {
                CachedTestingType(id: $0.rawValue, displayName: $0.defaultDisplayName, enabled: true)
            }
        }

        if let cached = TeamCustomizationCache.testingProcedures() {
            configs = cached
        }
    }

    private func saveTypesList() async {
        guard let orgId = supabase.organizationId else { return }
        isSavingList = true
        do {
            try await CustomizationSyncService.upsertTestingTypes(organizationId: orgId, types: types)
            TeamCustomizationCache.saveTestingTypes(types)
            listStatusMessage = "Saved."
        } catch {
            listStatusMessage = "Save failed: \(error.localizedDescription)"
            print("MYDEBUG →", "saveTypesList error: \(error)")
        }
        isSavingList = false
    }
}

// MARK: - Detail

struct TestingTypeDetailView: View {
    let typeId: String
    @Binding var types: [CachedTestingType]
    @Binding var configs: [String: CachedProcedureConfig]

    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var isSaving = false
    @State private var statusMessage: String?

    private var typeIndex: Int? {
        types.firstIndex { $0.id == typeId }
    }

    private func procedureBinding() -> Binding<CachedProcedureConfig> {
        Binding(
            get: { configs[typeId] ?? BuiltInTestingProcedureDefaults.defaultConfig(for: typeId) },
            set: { configs[typeId] = $0 }
        )
    }

    var body: some View {
        if let idx = typeIndex {
            List {
                Section {
                    TextField("Testing Type Title", text: $types[idx].displayName)
                    Toggle("Active", isOn: $types[idx].enabled)
                } footer: {
                    Text("When Active is on, field users can see this type after they sync. When off, it stays in your team list for existing jobs but is hidden for new work.")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ProcedureStepsEditorView(
                    testingTypeId: typeId,
                    windowTypesLinkLabel: types[idx].displayName,
                    config: procedureBinding()
                )

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(types[idx].displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveDetail() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving)
                }
            }
        } else {
            Text("Type not found.")
                .foregroundStyle(.secondary)
        }
    }

    private func saveDetail() async {
        guard typeIndex != nil, let orgId = supabase.organizationId else { return }
        isSaving = true
        do {
            try await CustomizationSyncService.upsertTestingTypes(organizationId: orgId, types: types)
            TeamCustomizationCache.saveTestingTypes(types)
            let proc = configs[typeId] ?? BuiltInTestingProcedureDefaults.defaultConfig(for: typeId)
            try await CustomizationSyncService.upsertTestingProcedure(
                organizationId: orgId, testingTypeId: typeId, config: proc
            )
            configs[typeId] = proc
            TeamCustomizationCache.saveTestingProcedures(configs)
            statusMessage = "Saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            print("MYDEBUG →", "saveDetail error: \(error)")
        }
        isSaving = false
    }
}
