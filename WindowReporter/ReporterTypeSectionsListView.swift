//
//  ReporterTypeSectionsListView.swift
//  WindowReporter
//
//  Specimen sections for a non-windows testing type.
//

import SwiftUI
import CoreData

struct ReporterTypeSectionsListView: View {
    let job: Job
    let testingTypeId: String
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTrigger = UUID()
    @State private var sectionToDelete: SpecimenSection?
    @State private var showingDeleteConfirmation = false
    @State private var isReordering = false

    private var sections: [SpecimenSection] {
        guard let set = job.specimenSections as? Set<SpecimenSection> else { return [] }
        return set.filter { $0.testingTypeId == testingTypeId }
            .sorted { a, b in
                if a.displayOrder != b.displayOrder { return a.displayOrder < b.displayOrder }
                return (a.sectionId ?? "") < (b.sectionId ?? "")
            }
    }

    private var typeDisplayName: String {
        TestingTypesHelper.displayName(for: testingTypeId, job: job)
    }

    private var typeIconName: String {
        switch testingTypeId {
        case "windows": return "square.grid.3x3"
        case "roof": return "house.fill"
        case "attic": return "arrow.up.to.line"
        case "floors": return "square.split.2x2"
        case "walls": return "rectangle.portrait"
        case "structural": return "hammer.fill"
        case "electrical": return "bolt.fill"
        case "moldMoisture": return "drop.fill"
        case "siding": return "square.stack.3d.up"
        case "doors": return "door.garage.closed"
        default: return "checklist"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(typeDisplayName) (\(sections.count))")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { withAnimation { isReordering.toggle() } }) {
                    Text(isReordering ? "Done" : "Reorder")
                }
                Button(action: addSection) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            if sections.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No \(typeDisplayName) sections")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Tap + to add a section")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(action: addSection) {
                        Image(systemName: "plus.circle.fill")
                            .font(.largeTitle)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections, id: \.sectionId) { section in
                        NavigationLink(destination: ReporterSectionEditorView(section: section)) {
                            ReporterSectionRowView(section: section)
                        }
                        .contextMenu {
                            Button(role: .destructive, action: { confirmDelete(section) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteSections)
                    .onMove(perform: moveSections)
                }
                .listStyle(.inset)
                #if os(iOS)
                .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
                #endif
            }
        }
        .navigationTitle(typeDisplayName)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: typeIconName)
                        .foregroundColor(.accentColor)
                    Text(typeDisplayName)
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: refreshTrigger) { _, _ in }
        .alert("Delete section?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { sectionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let s = sectionToDelete { deleteSection(s) }
                sectionToDelete = nil
            }
        } message: {
            Text("This section and its photos will be removed.")
        }
    }

    private func addSection() {
        let section = SpecimenSection(context: viewContext)
        section.sectionId = UUID().uuidString
        section.testingTypeId = testingTypeId
        let count = sections.count + 1
        section.sectionName = "Section \(count)"
        let maxOrder = sections.map { Int($0.displayOrder) }.max() ?? -1
        section.displayOrder = Int32(maxOrder + 1)
        section.xPosition = 0
        section.yPosition = 0
        section.createdAt = Date()
        section.updatedAt = Date()
        section.job = job
        do {
            try viewContext.save()
            print("MYDEBUG →", "Added \(typeDisplayName) section: \(section.sectionName ?? "")")
            refreshTrigger = UUID()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Failed to add section: \(error)")
        }
    }

    private func confirmDelete(_ section: SpecimenSection) {
        sectionToDelete = section
        showingDeleteConfirmation = true
    }

    private func deleteSection(_ section: SpecimenSection) {
        viewContext.delete(section)
        do {
            try viewContext.save()
            refreshTrigger = UUID()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Failed to delete section: \(error)")
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        var ordered = sections
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, section) in ordered.enumerated() {
            section.displayOrder = Int32(index)
        }
        do {
            try viewContext.save()
            refreshTrigger = UUID()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Reorder save failed: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }

    private func deleteSections(at offsets: IndexSet) {
        let ordered = sections
        for index in offsets where index < ordered.count {
            viewContext.delete(ordered[index])
        }
        try? viewContext.save()
        refreshTrigger = UUID()
        NotificationCenter.default.post(name: .jobDataUpdated, object: job)
    }
}

private struct ReporterSectionRowView: View {
    let section: SpecimenSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(section.sectionName ?? "Section")
                    .font(.headline)
                if (section.sectionPhotos?.count ?? 0) > 0 {
                    Spacer()
                    Label("\(section.sectionPhotos?.count ?? 0)", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let locNote = section.locationNote, !locNote.isEmpty {
                Text(locNote)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
            if let notes = section.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let result = section.result, !result.isEmpty {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(result == "Pass" ? .green : (result == "Fail" ? .red : .secondary))
            }
        }
        .padding(.vertical, 4)
    }
}
