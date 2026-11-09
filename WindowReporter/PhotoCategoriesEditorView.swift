//
//  PhotoCategoriesEditorView.swift
//  WindowReporter
//
//  Admin editor for photo note categories and captions. Lists photo types,
//  then categories per type, then caption options per category.
//

import SwiftUI

struct PhotoCategoriesEditorView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var payload: PhotoNoteCategoriesPayload = [:]
    @State private var isSaving = false
    @State private var statusMessage: String?

    private let photoTypes: [(key: String, label: String)] = [
        ("Exterior", "Exterior"),
        ("Interior", "Interior"),
        ("Leak", "Leak"),
        ("AAMA", "Certification Labels"),
        ("Interior Wide View", "Interior Wide View"),
        ("Interior Close-up & Damage", "Interior Close-up & Damage"),
        ("Leak Close-ups", "Leak Close-ups"),
        ("Exterior Wide View", "Exterior Wide View"),
        ("Exterior Photos", "Exterior Photos"),
    ]

    var body: some View {
        List {
            ForEach(photoTypes, id: \.key) { pt in
                NavigationLink {
                    CategoryListEditor(
                        photoTypeKey: pt.key,
                        photoTypeLabel: pt.label,
                        items: binding(for: pt.key),
                        onSave: { items in await saveType(pt.key, items: items) }
                    )
                } label: {
                    HStack {
                        Text(pt.label)
                        Spacer()
                        let count = payload[pt.key]?.count ?? 0
                        Text(count > 0 ? "\(count) categories" : "default")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
        .navigationTitle("Photo Categories")
        .task { await loadFromSupabase() }
    }

    private func binding(for key: String) -> Binding<[PhotoNoteCategoryItem]> {
        Binding(
            get: { payload[key] ?? builtInItems(for: key) },
            set: { payload[key] = $0 }
        )
    }

    private func builtInItems(for key: String) -> [PhotoNoteCategoryItem] {
        guard let photoType = PhotoType(rawValue: key) else { return [] }
        return PhotoNoteCategories.builtInCategories(for: photoType)
            .map { PhotoNoteCategoryItem(name: $0.name, options: $0.options) }
    }

    private func loadFromSupabase() async {
        guard let orgId = supabase.organizationId else { return }
        await CustomizationSyncService.syncPhotoCategories(organizationId: orgId)
        if let cached = TeamCustomizationCache.photoCategories() {
            payload = cached
        }
    }

    private func saveType(_ key: String, items: [PhotoNoteCategoryItem]) async {
        guard let orgId = supabase.organizationId else { return }
        isSaving = true
        do {
            try await CustomizationSyncService.upsertPhotoCategories(
                organizationId: orgId, photoType: key, categories: items
            )
            payload[key] = items
            TeamCustomizationCache.savePhotoCategories(payload)
            statusMessage = "Saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            print("MYDEBUG →", "saveType error: \(error)")
        }
        isSaving = false
    }
}

// MARK: - Category list for one photo type

private struct CategoryListEditor: View {
    let photoTypeKey: String
    let photoTypeLabel: String
    @Binding var items: [PhotoNoteCategoryItem]
    let onSave: ([PhotoNoteCategoryItem]) async -> Void

    @State private var draft: [EditableCategory] = []
    @State private var isSaving = false
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        List {
            ForEach($draft) { $cat in
                NavigationLink {
                    CaptionListEditor(category: $cat)
                } label: {
                    HStack {
                        Text(cat.name)
                        Spacer()
                        Text(cat.options.isEmpty ? "custom text" : "\(cat.options.count) captions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { indexSet in draft.remove(atOffsets: indexSet) }
            .onMove { from, to in draft.move(fromOffsets: from, toOffset: to) }

            Button {
                showingAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus")
            }
        }
        .navigationTitle(photoTypeLabel)
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
        .alert("New Category", isPresented: $showingAddCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                draft.append(EditableCategory(name: trimmed, options: []))
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
        .onAppear {
            draft = items.map { EditableCategory(name: $0.name, options: $0.options) }
        }
    }

    private func save() async {
        isSaving = true
        let result = draft.map { PhotoNoteCategoryItem(name: $0.name, options: $0.options) }
        await onSave(result)
        items = result
        isSaving = false
    }
}

// MARK: - Caption list for one category

private struct CaptionListEditor: View {
    @Binding var category: EditableCategory
    @State private var newCaption = ""

    var body: some View {
        List {
            Section {
                TextField("Category Name", text: $category.name)
                    .padding(.vertical, 4)
            }

            Section("Captions") {
                if category.options.isEmpty {
                    Text("No preset captions — users will type custom text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(category.options.indices, id: \.self) { index in
                    TextField("Caption", text: $category.options[index], axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.vertical, 3)
                }
                .onDelete { indexSet in category.options.remove(atOffsets: indexSet) }
                .onMove { from, to in category.options.move(fromOffsets: from, toOffset: to) }

                HStack {
                    TextField("New caption…", text: $newCaption, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        let trimmed = newCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        category.options.append(trimmed)
                        newCaption = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle(category.name)
    }
}

// MARK: - Editable model

private struct EditableCategory: Identifiable {
    let id = UUID()
    var name: String
    var options: [String]
}
