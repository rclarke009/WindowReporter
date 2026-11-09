//
//  WindowTypesEditorView.swift
//  WindowReporter
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WindowTypesEditorView: View {
    let testingTypeId: String
    let testingTypeLabel: String

    @ObservedObject private var supabase = SupabaseManager.shared

    @State private var fullConfig: CachedWindowTypesByScope = CachedWindowTypesByScope()
    @State private var types: [String] = []
    @State private var initialTypesInScope: [String] = []
    @State private var remoteImagePaths: [String: String] = [:]
    @State private var pendingImageData: [String: Data] = [:]
    @State private var pendingRemovals: Set<String> = []
    @State private var isSaving = false
    @State private var showingAddType = false
    @State private var newTypeName = ""
    @State private var statusMessage: String?
    @State private var showFileImporter = false
    @State private var photoTargetType: String?
    @State private var initialRemoteAtLoad: [String: String] = [:]

    private var screenTitle: String { "\(testingTypeLabel) types" }

    private var builtInDefault: [String] { WindowTypeBuiltInList.defaultOrder }

    private var isWindowsType: Bool { testingTypeId == TestingTypeId.windows.rawValue }

    var body: some View {
        List {
            Section {
                ForEach(types, id: \.self) { t in
                    windowTypeRow(typeName: t)
                }
                .onDelete { indexSet in types.remove(atOffsets: indexSet) }
                .onMove { from, to in types.move(fromOffsets: from, toOffset: to) }
            } footer: {
                Text("These names appear in the field app for this testing type. Reference images are keyed by name across the team.")
            }

            Section {
                Button {
                    showingAddType = true
                } label: {
                    Label("Add type", systemImage: "plus")
                }

                if shouldShowReset {
                    Button("Reset to Defaults") {
                        if isWindowsType {
                            types = builtInDefault
                        } else {
                            types = []
                        }
                        pendingImageData = [:]
                        for name in remoteImagePaths.keys { pendingRemovals.insert(name) }
                    }
                    .foregroundStyle(.orange)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(screenTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(isSaving)
            }
        }
        .alert(alertTitle, isPresented: $showingAddType) {
            TextField("Name", text: $newTypeName)
            Button("Add") {
                addNewType()
            }
            Button("Cancel", role: .cancel) { newTypeName = "" }
        }
        .task { await load() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.image, .jpeg, .png, .heic],
            allowsMultipleSelection: false
        ) { result in
            guard let t = photoTargetType else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url) {
                    pendingImageData[t] = d
                    pendingRemovals.remove(t)
                }
            case .failure:
                break
            }
            photoTargetType = nil
        }
    }

    private var alertTitle: String { "New “\(testingTypeLabel)” type" }

    private var shouldShowReset: Bool {
        if isWindowsType { return types != builtInDefault }
        return !types.isEmpty
    }

    private func addNewType() {
        let trimmed = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !types.contains(trimmed) else { return }
        types.append(trimmed)
        newTypeName = ""
    }

    @ViewBuilder
    private func windowTypeRow(typeName: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            rowThumbnail(typeName: typeName)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            Text(typeName)
                .lineLimit(2)

            Spacer()

            Menu {
                Button {
                    photoTargetType = typeName
                    showFileImporter = true
                } label: {
                    Label("Set image…", systemImage: "photo")
                }
                if hasImage(typeName: typeName) {
                    Button(role: .destructive) {
                        pendingImageData.removeValue(forKey: typeName)
                        pendingRemovals.insert(typeName)
                    } label: {
                        Label("Remove image", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowThumbnail(typeName: String) -> some View {
        if let d = pendingImageData[typeName], let img = NSImage(data: d) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else if !pendingRemovals.contains(typeName), let img = TeamCustomizationCache.windowTypeImage(for: typeName) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    private func hasImage(typeName: String) -> Bool {
        if pendingRemovals.contains(typeName) { return false }
        if pendingImageData[typeName] != nil { return true }
        if TeamCustomizationCache.windowTypeImage(for: typeName) != nil { return true }
        return false
    }

    private func load() async {
        guard let orgId = supabase.organizationId else { return }
        await CustomizationSyncService.syncWindowTypes(organizationId: orgId)
        let full = TeamCustomizationCache.windowTypesByScope() ?? CachedWindowTypesByScope()
        fullConfig = full
        if let list = full.byTestingTypeId[testingTypeId] {
            types = list
        } else {
            types = isWindowsType ? builtInDefault : []
        }
        initialTypesInScope = types
        remoteImagePaths = TeamCustomizationCache.windowTypeImageRemotePaths() ?? [:]
        initialRemoteAtLoad = remoteImagePaths
    }

    private func save() async {
        guard let orgId = supabase.organizationId else { return }
        isSaving = true
        do {
            var merged = fullConfig
            merged.setListForTestingTypeId(testingTypeId, names: types)
            let newUnion = Set(merged.unionTypeNames())

            var newRemote = remoteImagePaths
            for name in pendingRemovals {
                if let path = newRemote.removeValue(forKey: name) {
                    try? await supabase.deleteWindowTypeImage(path: path)
                }
            }
            for (name, data) in pendingImageData {
                if let old = newRemote[name] {
                    try? await supabase.deleteWindowTypeImage(path: old)
                }
                let path = try await supabase.uploadWindowTypeImage(organizationId: orgId, typeName: name, imageData: data)
                newRemote[name] = path
            }
            for oldName in initialTypesInScope where !types.contains(oldName) {
                guard !newUnion.contains(oldName) else { continue }
                if let path = newRemote.removeValue(forKey: oldName) {
                    try? await supabase.deleteWindowTypeImage(path: path)
                } else if let path = initialRemoteAtLoad[oldName] {
                    try? await supabase.deleteWindowTypeImage(path: path)
                }
            }
            let filtered = newRemote.filter { newUnion.contains($0.key) }
            try await CustomizationSyncService.upsertWindowTypes(organizationId: orgId, scope: merged, typeImages: filtered)
            TeamCustomizationCache.saveWindowTypesByScope(merged)
            await CustomizationSyncService.syncWindowTypes(organizationId: orgId)
            remoteImagePaths = TeamCustomizationCache.windowTypeImageRemotePaths() ?? [:]
            fullConfig = merged
            initialTypesInScope = types
            pendingImageData = [:]
            pendingRemovals = []
            statusMessage = "Saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            print("MYDEBUG →", "saveWindowTypes error: \(error)")
        }
        isSaving = false
    }
}
