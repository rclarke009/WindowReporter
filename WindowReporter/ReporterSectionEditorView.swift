//
//  ReporterSectionEditorView.swift
//  WindowReporter
//
//  Edit specimen section fields (parity with field app SectionEditorView, minus live weather API).
//

import SwiftUI
import CoreData

struct ReporterSectionEditorView: View {
    @ObservedObject var section: SpecimenSection
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var sectionName: String
    @State private var notes: String
    @State private var result: String
    @State private var showingLocationMarker = false
    @State private var showingDeleteAlert = false
    @State private var showingPhotoGallery = false
    @State private var locationNote: String
    @State private var roomOrAreaPaintAnswer: String
    @State private var persistTask: Task<Void, Never>?

    private let resultOptions = ["", "Pending", "Pass", "Fail", "N/A"]
    private static let persistDebounceNanos: UInt64 = 400_000_000

    init(section: SpecimenSection) {
        _section = ObservedObject(wrappedValue: section)
        _sectionName = State(initialValue: section.sectionName ?? "")
        _notes = State(initialValue: section.notes ?? "")
        _result = State(initialValue: section.result ?? "")
        _locationNote = State(initialValue: section.locationNote ?? "")
        _roomOrAreaPaintAnswer = State(initialValue: section.roomOrAreaPaintAnswer ?? "")
    }

    private var locationNotePlaceholder: String {
        let typeName = TestingTypesHelper.displayName(for: section.testingTypeId ?? "", job: section.job)
            .lowercased()
        let singular = typeName.hasSuffix("s") ? String(typeName.dropLast()) : typeName
        return "e.g. 1st \(singular) on the left or northmost \(singular)"
    }

    var body: some View {
        Form {
            Section {
                TextField(locationNotePlaceholder, text: $locationNote, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: locationNote) { _, _ in schedulePersistSection() }
            } header: {
                Text("Location Number or Note")
            }
            Section {
                TextField("When this room or area was painted (year, approx., N/A, etc.)", text: $roomOrAreaPaintAnswer, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: roomOrAreaPaintAnswer) { _, _ in schedulePersistSection() }
            } header: {
                Text("Room / area paint")
            }
            if let job = section.job {
                Section {
                    Toggle("Use job environmental data", isOn: Binding(
                        get: { section.usesJobEnvironmentalDefaults },
                        set: { newVal in
                            if newVal {
                                SpecimenEnvironmental.clearSpecimenEnvironmentalOverride(section: section)
                            } else {
                                section.usesJobEnvironmentalDefaults = false
                                SpecimenEnvironmental.copyJobEnvironmentalSnapshot(from: job, to: section)
                            }
                            section.updatedAt = Date()
                            try? viewContext.save()
                            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
                        }
                    ))
                    if !section.usesJobEnvironmentalDefaults {
                        DatePicker("Inspection date", selection: Binding(
                            get: { section.specimenInspectionDate ?? job.inspectionDate ?? Date() },
                            set: { newDate in
                                section.specimenInspectionDate = newDate
                                section.usesJobEnvironmentalDefaults = false
                                section.updatedAt = Date()
                                try? viewContext.save()
                                NotificationCenter.default.post(name: .jobDataUpdated, object: job)
                            }
                        ), displayedComponents: .date)
                        let w = SpecimenEnvironmental.effectiveDisplayWeather(section: section, job: job)
                        Text(String(format: "Temp: %.0f °F  •  Wind: %.0f mph", w.temperature, w.windSpeed))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let cond = section.specimenWeatherCondition, !cond.isEmpty {
                            Text(cond)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("Adjust job-level weather on the job overview, or clear overrides to copy from the job again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("This specimen uses the inspection date and weather from the job. Turn off the toggle to set values for this specimen only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Inspection & weather (this specimen)")
                }
            }
            Section("Section") {
                TextField("Name", text: $sectionName)
                    .onChange(of: sectionName) { _, _ in schedulePersistSection() }
            }
            Section("Result") {
                Picker("Result", selection: $result) {
                    Text("—").tag("")
                    ForEach(resultOptions.dropFirst(), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .onChange(of: result) { _, _ in schedulePersistSection() }
            }
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .onChange(of: notes) { _, _ in schedulePersistSection() }
            }
            Section("Photos") {
                let photoCount = (section.sectionPhotos?.count ?? 0)
                Button(action: { showingPhotoGallery = true }) {
                    HStack {
                        Label("Section Photos", systemImage: "photo.on.rectangle")
                        Spacer()
                        if photoCount > 0 {
                            Text("\(photoCount)")
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("Location on overhead") {
                if section.xPosition != 0 || section.yPosition != 0 {
                    Text("Location marked")
                        .foregroundColor(.secondary)
                }
                Button(showingLocationMarker ? "Cancel" : "Mark location on overhead") {
                    showingLocationMarker.toggle()
                }
            }
            Section {
                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                    Label("Delete section", systemImage: "trash")
                }
            }
        }
        .navigationTitle(sectionName.isEmpty ? "Section" : sectionName)
        .sheet(isPresented: $showingLocationMarker) {
            if let job = section.job {
                ReporterSectionLocationMarkerView(section: section, job: job)
                    .environment(\.managedObjectContext, viewContext)
                    .onDisappear { showingLocationMarker = false }
            }
        }
        .sheet(isPresented: $showingPhotoGallery) {
            ReporterSectionPhotoGalleryView(section: section)
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete this section?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let j = section.job
                viewContext.delete(section)
                try? viewContext.save()
                if let j { NotificationCenter.default.post(name: .jobDataUpdated, object: j) }
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
        .onDisappear {
            persistTask?.cancel()
            persistTask = nil
            flushPersistSectionIfNeeded()
        }
    }

    private func schedulePersistSection() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.persistDebounceNanos)
            guard !Task.isCancelled else { return }
            persistTask = nil
            persistSectionFromState()
        }
    }

    private func flushPersistSectionIfNeeded() {
        guard section.managedObjectContext != nil, !section.isDeleted else { return }
        persistSectionFromState()
    }

    private func persistSectionFromState() {
        guard section.managedObjectContext != nil, !section.isDeleted else { return }
        section.sectionName = sectionName
        section.notes = notes.isEmpty ? nil : notes
        section.result = result.isEmpty ? nil : result
        section.locationNote = locationNote.isEmpty ? nil : locationNote
        let paintTrim = roomOrAreaPaintAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        section.roomOrAreaPaintAnswer = paintTrim.isEmpty ? nil : paintTrim
        section.updatedAt = Date()
        do {
            try viewContext.save()
            if let job = section.job {
                NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            }
        } catch {
            print("MYDEBUG →", "ReporterSectionEditorView save failed: \(error.localizedDescription)")
        }
    }
}
