//
//  PhotoNoteCategoriesEditorView.swift
//  WindowReporter
//
//  Edit photo note categories and caption options per photo type. Exported packages send this to the field app.
//

import SwiftUI
import AppKit

private struct CategoriesSharePickerView: NSViewRepresentable {
    @Binding var isPresented: Bool
    var items: [Any]

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented, !items.isEmpty {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = context.coordinator
            DispatchQueue.main.async {
                picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        @Binding var isPresented: Bool
        init(isPresented: Binding<Bool>) { _isPresented = isPresented }
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            isPresented = false
        }
    }
}

struct PhotoNoteCategoriesEditorView: View {
    @StateObject private var store = PhotoNoteCategoriesStore.shared
    @AppStorage("inspectorName") private var inspectorName: String = ""
    @State private var selectedPhotoTypeRaw: String?
    @FocusState private var focusedCaptionField: CaptionField?
    @State private var isExportingCategories = false
    @State private var isExportingCategoriesCSV = false
    @State private var categoriesPackageError: String?
    @State private var categoriesExportFileURL: URL?
    @State private var showCategoriesShare = false
    @State private var showAddCategoryPrompt = false
    @State private var addCategoryName = ""
    @State private var addCategoryPhotoTypeRaw: String?
    
    var body: some View {
        List(selection: $selectedPhotoTypeRaw) {
            Section {
                Button(action: exportAndShareCategoriesPackage) {
                    HStack {
                        if isExportingCategories {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExportingCategories ? "Preparing package..." : "Send categories/captions to another user")
                    }
                }
                .disabled(isExportingCategories || isExportingCategoriesCSV)

                Button(action: exportCategoriesCSV) {
                    HStack {
                        if isExportingCategoriesCSV {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "tablecells")
                        }
                        Text(isExportingCategoriesCSV ? "Exporting CSV..." : "Export captions/categories CSV")
                    }
                }
                .disabled(isExportingCategories || isExportingCategoriesCSV)

                if let error = categoriesPackageError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if let fileURL = categoriesExportFileURL {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Exported: \(fileURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Share…") {
                            showCategoriesShare = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                Text("Use ZIP for app-to-app import, or CSV for spreadsheets/databases.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            } header: {
                Text("Transfer")
                    .padding(.top, 8)
            }
            .listRowSeparator(.hidden)

            ForEach(PhotoType.photoTypesUsedInFieldApp, id: \.rawValue) { photoType in
                DisclosureGroup(isExpanded: bindingExpanded(for: photoType.rawValue)) {
                    categoriesContent(for: photoType)
                } label: {
                    Label(photoType.rawValue, systemImage: photoType.icon)
                        .foregroundColor(photoType.color)
                        .padding(.top, 8)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .padding(.horizontal, 8)
        .navigationTitle("Photo Categories")
        .frame(minWidth: 500, idealWidth: 560, minHeight: 620, idealHeight: 860)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset to defaults") {
                    store.resetToDefaults()
                }
            }
        }
        .background(CategoriesSharePickerView(isPresented: $showCategoriesShare, items: categoriesExportFileURL.map { [$0] } ?? []))
        .sheet(isPresented: $showAddCategoryPrompt) {
            addCategorySheet
        }
    }
    
    @State private var expandedPhotoTypes: Set<String> = Set(PhotoType.photoTypesUsedInFieldApp.map(\.rawValue))
    
    private struct CaptionField: Hashable {
        let photoTypeRaw: String
        let categoryIndex: Int
        let optionIndex: Int
    }
    
    private func bindingExpanded(for raw: String) -> Binding<Bool> {
        Binding(
            get: { expandedPhotoTypes.contains(raw) },
            set: { if $0 { expandedPhotoTypes.insert(raw) } else { expandedPhotoTypes.remove(raw) } }
        )
    }
    
    @ViewBuilder
    private func categoriesContent(for photoType: PhotoType) -> some View {
        let raw = photoType.rawValue
        let binding = bindingForPhotoType(raw)
        
        ForEach(Array((binding.wrappedValue).enumerated()), id: \.offset) { index, _ in
            categoryRow(binding: binding, index: index, photoTypeRaw: raw)
        }
        .onDelete { indexSet in
            var list = binding.wrappedValue
            list.remove(atOffsets: indexSet)
            store.setCategories(list, forPhotoTypeRaw: raw)
        }
        
        Button(action: {
            addCategoryPhotoTypeRaw = raw
            addCategoryName = ""
            showAddCategoryPrompt = true
        }) {
            Label("Add category", systemImage: "plus.circle")
        }
    }
    
    private func bindingForPhotoType(_ raw: String) -> Binding<[PhotoNoteCategoryItem]> {
        Binding(
            get: { store.categories(forPhotoTypeRaw: raw) },
            set: { store.setCategories($0, forPhotoTypeRaw: raw) }
        )
    }
    
    private func categoryRow(binding: Binding<[PhotoNoteCategoryItem]>, index: Int, photoTypeRaw: String) -> some View {
        let catBinding = Binding<PhotoNoteCategoryItem>(
            get: { index < binding.wrappedValue.count ? binding.wrappedValue[index] : PhotoNoteCategoryItem(name: "", options: []) },
            set: { new in
                var list = binding.wrappedValue
                if index < list.count {
                    list[index] = new
                    store.setCategories(list, forPhotoTypeRaw: photoTypeRaw)
                }
            }
        )
        let nameBinding = Binding<String>(
            get: { catBinding.wrappedValue.name },
            set: { var c = catBinding.wrappedValue; c.name = $0; catBinding.wrappedValue = c }
        )
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Category name", text: nameBinding)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: 340, alignment: .leading)
            
            ForEach(Array((catBinding.wrappedValue.options).enumerated()), id: \.offset) { optIndex, _ in
                let captionField = CaptionField(
                    photoTypeRaw: photoTypeRaw,
                    categoryIndex: index,
                    optionIndex: optIndex
                )
                let isFocused = focusedCaptionField == captionField
                
                HStack(alignment: .top) {
                    TextField("Caption option", text: Binding(
                        get: { optIndex < catBinding.wrappedValue.options.count ? catBinding.wrappedValue.options[optIndex] : "" },
                        set: { val in
                            var cat = catBinding.wrappedValue
                            if optIndex < cat.options.count {
                                cat.options[optIndex] = val
                                catBinding.wrappedValue = cat
                            }
                        }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .font(isFocused ? .title2.weight(.semibold) : .title3)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360, alignment: .leading)
                    .focused($focusedCaptionField, equals: captionField)
                    Button(role: .destructive) {
                        var cat = catBinding.wrappedValue
                        if optIndex < cat.options.count {
                            cat.options.remove(at: optIndex)
                            catBinding.wrappedValue = cat
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button(action: {
                var cat = catBinding.wrappedValue
                cat.options.append("")
                catBinding.wrappedValue = cat
            }) {
                Label("Add caption option", systemImage: "text.badge.plus")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func exportAndShareCategoriesPackage() {
        guard let payload = store.exportPayload(), !payload.isEmpty else {
            categoriesPackageError = "No categories to export."
            return
        }

        categoriesPackageError = nil
        isExportingCategories = true

        Task {
            do {
                let name = inspectorName.trimmingCharacters(in: .whitespacesAndNewlines)
                let exporter = PhotoNoteCategoriesPackageExporter(
                    payload: payload,
                    exportedBy: name.isEmpty ? nil : name
                )
                let fileURL = try await exporter.export()
                await MainActor.run {
                    categoriesExportFileURL = fileURL
                    showCategoriesShare = true
                    isExportingCategories = false
                }
            } catch {
                await MainActor.run {
                    categoriesPackageError = error.localizedDescription
                    isExportingCategories = false
                }
            }
        }
    }

    private func exportCategoriesCSV() {
        guard let payload = store.exportPayload(), !payload.isEmpty else {
            categoriesPackageError = "No categories to export."
            return
        }

        categoriesPackageError = nil
        isExportingCategoriesCSV = true

        Task {
            do {
                let exporter = PhotoNoteCategoriesCSVExporter(payload: payload)
                let fileURL = try exporter.export()
                await MainActor.run {
                    categoriesExportFileURL = fileURL
                    showCategoriesShare = true
                    isExportingCategoriesCSV = false
                }
            } catch {
                await MainActor.run {
                    categoriesPackageError = error.localizedDescription
                    isExportingCategoriesCSV = false
                }
            }
        }
    }

    @ViewBuilder
    private var addCategorySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Category")
                .font(.headline)
            TextField("Category name", text: $addCategoryName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    showAddCategoryPrompt = false
                    addCategoryPhotoTypeRaw = nil
                    addCategoryName = ""
                }
                Button("Add") {
                    addCategoryFromPrompt()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(addCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private func addCategoryFromPrompt() {
        let name = addCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let raw = addCategoryPhotoTypeRaw else { return }
        var list = store.categories(forPhotoTypeRaw: raw)
        list.append(PhotoNoteCategoryItem(name: name, options: []))
        store.setCategories(list, forPhotoTypeRaw: raw)
        showAddCategoryPrompt = false
        addCategoryPhotoTypeRaw = nil
        addCategoryName = ""
    }
}

#Preview {
    NavigationStack {
        PhotoNoteCategoriesEditorView()
    }
    .frame(width: 500, height: 500)
}
