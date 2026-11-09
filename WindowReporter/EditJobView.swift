//
//  EditJobView.swift
//  WindowReporter
//
//  macOS version
//

import SwiftUI
import CoreData
import AppKit
import PhotosUI
import UniformTypeIdentifiers

struct EditJobView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let job: Job
    
    @State private var jobId: String
    @State private var clientName: String
    @State private var tenantName: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String
    @State private var notes: String
    @State private var phoneNumber: String
    @State private var areasOfConcern: String
    @State private var inspectorName: String
    @State private var inspectionDate: Date
    @State private var status: String
    @State private var testProcedure: String
    @State private var waterPressure: String
    @State private var overheadImageSourceName: String
    @State private var overheadImageSourceUrl: String
    @State private var scalePixelsPerFoot: String
    @State private var enabledTestingTypeIds: Set<String>
    @State private var testingTypeNote: [String: String]
    
    @State private var showingImagePicker = false
    @State private var showingCalibrationImagePicker = false
    @State private var showingOverheadSourcePicker = false
    @State private var showingCalibrationSourcePicker = false
    @State private var showingOverheadPhotosPicker = false
    @State private var showingCalibrationPhotosPicker = false
    @State private var selectedOverheadPhotosItem: PhotosPickerItem?
    @State private var selectedCalibrationPhotosItem: PhotosPickerItem?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let statusOptions = ["Ready", "In Progress", "Completed", "Failed"]
    
    init(job: Job) {
        self.job = job
        _jobId = State(initialValue: job.jobId ?? "")
        _clientName = State(initialValue: job.clientName ?? "")
        _tenantName = State(initialValue: job.tenantName ?? "")
        _addressLine1 = State(initialValue: job.addressLine1 ?? "")
        _city = State(initialValue: job.city ?? "")
        _state = State(initialValue: job.state ?? "")
        _zip = State(initialValue: job.zip ?? "")
        _notes = State(initialValue: job.notes ?? "")
        _phoneNumber = State(initialValue: job.phoneNumber ?? "")
        _areasOfConcern = State(initialValue: job.areasOfConcern ?? "")
        _inspectorName = State(initialValue: job.inspectorName ?? "")
        _inspectionDate = State(initialValue: job.inspectionDate ?? Date())
        _status = State(initialValue: job.status ?? "Ready")
        _testProcedure = State(initialValue: job.testProcedure ?? "ASTM E1105")
        _waterPressure = State(initialValue: job.waterPressure > 0 ? String(format: "%.0f", job.waterPressure) : "12")
        _overheadImageSourceName = State(initialValue: job.overheadImageSourceName ?? "")
        _overheadImageSourceUrl = State(initialValue: job.overheadImageSourceUrl ?? "")
        _scalePixelsPerFoot = State(initialValue: String(job.scalePixelsPerFoot))
        let ids: Set<String> = {
            guard let raw = job.enabledTestingTypeIds?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                let defaultRaw = UserDefaults.standard.string(forKey: "defaultEnabledTestingTypeIds")?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let r = defaultRaw, !r.isEmpty {
                    return Set(r.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                }
                return ["windows"]
            }
            return Set(raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }()
        let typeNotes: [String: String] = {
            if let raw = job.testingTypeNotes?.data(using: .utf8), let decoded = try? JSONDecoder().decode([String: String].self, from: raw), !decoded.isEmpty {
                return decoded
            }
            if let defaultRaw = UserDefaults.standard.string(forKey: "defaultTestingTypeNotes"),
               let data = defaultRaw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        _enabledTestingTypeIds = State(initialValue: ids)
        _testingTypeNote = State(initialValue: typeNotes)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Job Information") {
                    TextField("Job ID", text: $jobId)
                    TextField("Client Name", text: $clientName)
                    TextField("Tenant Name", text: $tenantName)
                    TextField("Address Line 1", text: $addressLine1)
                    HStack {
                        TextField("City", text: $city)
                        TextField("State", text: $state)
                            .frame(width: 80)
                        TextField("ZIP", text: $zip)
                            .frame(width: 100)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Phone Number", text: $phoneNumber)
                    TextField("Areas of Concern", text: $areasOfConcern, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Inspector Information") {
                    TextField("Inspector Name", text: $inspectorName)
                    DatePicker("Inspection Date", selection: $inspectionDate, displayedComponents: .date)
                    Picker("Status", selection: $status) {
                        ForEach(statusOptions, id: \.self) { statusOption in
                            Text(statusOption).tag(statusOption)
                        }
                    }
                }
                
                Section("Test Information") {
                    TextField("Test Procedure", text: $testProcedure)
                    TextField("Water (PSI)", text: $waterPressure)
                        .frame(maxWidth: 120)
                }
                
                Section {
                    Text("Types of testing the client requested. Exported packages will send this list to the field app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: { Text("Testing") }
                Section("Testing types") {
                    ForEach(TeamTestingTypesOrdering.rowsForToggles(currentSelection: enabledTestingTypeIds, job: job), id: \.id) { typeItem in
                        let binding = Binding(
                            get: { enabledTestingTypeIds.contains(typeItem.id) },
                            set: { enabled in
                                if enabled { enabledTestingTypeIds.insert(typeItem.id) }
                                else {
                                    enabledTestingTypeIds.remove(typeItem.id)
                                    testingTypeNote.removeValue(forKey: typeItem.id)
                                }
                            }
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(typeItem.name, isOn: binding)
                            if enabledTestingTypeIds.contains(typeItem.id) {
                                TextField("Note for this type (optional)", text: Binding(
                                    get: { testingTypeNote[typeItem.id] ?? "" },
                                    set: { testingTypeNote[typeItem.id] = $0.isEmpty ? nil : $0 }
                                ), axis: .vertical)
                                    .lineLimit(1...3)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                Section("Overhead Image") {
                    if let currentImage = loadCurrentOverheadImage() {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Image")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(nsImage: currentImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .cornerRadius(8)
                                .onTapGesture(count: 2) {
                                    showingOverheadSourcePicker = true
                                }
                        }
                    }
                    
                    Button(action: {
                        showingOverheadSourcePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            Text(job.overheadImagePath != nil ? "Replace Image" : "Select Overhead Image")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section("Equipment Calibration Photos") {
                    if let currentImage = loadCurrentCalibrationImage() {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Image")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(nsImage: currentImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .cornerRadius(8)
                                .onTapGesture(count: 2) {
                                    showingCalibrationSourcePicker = true
                                }
                        }
                    }
                    
                    Button(action: {
                        showingCalibrationSourcePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            Text(hasCurrentCalibrationImage() ? "Replace Image" : "Add Calibration Photo")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(minWidth: 800, idealWidth: 1000, maxWidth: .infinity, minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle("Edit Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJob()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImagePicker,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                handleImageSelection(result: result)
            }
            .fileImporter(
                isPresented: $showingCalibrationImagePicker,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                handleCalibrationImageSelection(result: result)
            }
            .photosPicker(
                isPresented: $showingOverheadPhotosPicker,
                selection: $selectedOverheadPhotosItem,
                matching: .images
            )
            .photosPicker(
                isPresented: $showingCalibrationPhotosPicker,
                selection: $selectedCalibrationPhotosItem,
                matching: .images
            )
            .onChange(of: selectedOverheadPhotosItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = NSImage(data: data) {
                        await MainActor.run {
                            replaceOverheadImageImmediately(image)
                            selectedOverheadPhotosItem = nil
                        }
                    }
                }
            }
            .onChange(of: selectedCalibrationPhotosItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = NSImage(data: data) {
                        await MainActor.run {
                            replaceCalibrationImageImmediately(image)
                            selectedCalibrationPhotosItem = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showingOverheadSourcePicker) {
                EditImageSourcePickerSheet(
                    title: job.overheadImagePath != nil ? "Replace Overhead Image" : "Add Overhead Image",
                    onPhotosSelected: {
                        showingOverheadSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingOverheadPhotosPicker = true
                        }
                    },
                    onFileSelected: {
                        showingOverheadSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingImagePicker = true
                        }
                    },
                    onCancel: {
                        showingOverheadSourcePicker = false
                    }
                )
            }
            .sheet(isPresented: $showingCalibrationSourcePicker) {
                EditImageSourcePickerSheet(
                    title: hasCurrentCalibrationImage() ? "Replace Calibration Image" : "Add Calibration Image",
                    onPhotosSelected: {
                        showingCalibrationSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingCalibrationPhotosPicker = true
                        }
                    },
                    onFileSelected: {
                        showingCalibrationSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingCalibrationImagePicker = true
                        }
                    },
                    onCancel: {
                        showingCalibrationSourcePicker = false
                    }
                )
            }
            .alert("Job Updated", isPresented: $showingAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func handleImageSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if let image = NSImage(contentsOf: url) {
                replaceOverheadImageImmediately(image)
            }
        case .failure:
            break
        }
    }
    
    private func handleCalibrationImageSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if let image = NSImage(contentsOf: url) {
                replaceCalibrationImageImmediately(image)
            }
        case .failure:
            break
        }
    }
    
    private func loadCurrentOverheadImage() -> NSImage? {
        guard let imagePath = job.overheadImagePath else { return nil }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
        return NSImage(contentsOf: imageURL)
    }
    
    private func loadCurrentCalibrationImage() -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Prefer imported/exported equipment calibration slots; fall back to legacy gauge path.
        let calibrationCandidates: [(directory: String, path: String)] = [
            ("equipment_calibration", job.equipmentCalibrationImage1Path ?? ""),
            ("equipment_calibration", job.equipmentCalibrationImage2Path ?? ""),
            ("gauge_images", job.gaugeImagePath ?? "")
        ]
        
        for candidate in calibrationCandidates where !candidate.path.isEmpty {
            let imageURL = documentsDirectory.appendingPathComponent(candidate.directory).appendingPathComponent(candidate.path)
            if let image = NSImage(contentsOf: imageURL) {
                return image
            }
        }
        
        return nil
    }

    private func hasCurrentCalibrationImage() -> Bool {
        loadCurrentCalibrationImage() != nil
    }
    
    private func saveJob() {
        job.jobId = jobId
        job.clientName = clientName
        job.tenantName = blankToNil(tenantName)
        job.addressLine1 = addressLine1
        job.cleanedAddressLine1 = AddressCleaningUtility.cleanAddress(addressLine1)
        job.city = city
        job.state = state
        job.zip = zip
        job.notes = notes.isEmpty ? nil : notes
        job.phoneNumber = phoneNumber.isEmpty ? nil : phoneNumber
        job.areasOfConcern = areasOfConcern.isEmpty ? nil : areasOfConcern
        job.inspectorName = inspectorName.isEmpty ? nil : inspectorName
        job.inspectionDate = inspectionDate
        job.status = status
        job.testProcedure = testProcedure
        job.waterPressure = Double(waterPressure) ?? 12.0
        job.overheadImageSourceName = overheadImageSourceName.isEmpty ? nil : overheadImageSourceName
        job.overheadImageSourceUrl = overheadImageSourceUrl.isEmpty ? nil : overheadImageSourceUrl
        job.scalePixelsPerFoot = Double(scalePixelsPerFoot) ?? 10.0
        job.enabledTestingTypeIds = TeamTestingTypesOrdering.commaJoinedPreservingOrder(enabledIds: enabledTestingTypeIds)
        let notesToSave = testingTypeNote.filter { !($0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        job.testingTypeNotes = notesToSave.isEmpty ? nil : (try? JSONEncoder().encode(notesToSave)).flatMap { String(data: $0, encoding: .utf8) }
        JobTestingTypeDisplayNameSnapshot.merge(into: job, enabledTypeIds: TestingTypesHelper.enabledTypeIds(from: job))
        job.updatedAt = Date()
        
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            alertMessage = "Job updated successfully!"
            showingAlert = true
        } catch {
            alertMessage = "Failed to update job: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func replaceOverheadImageImmediately(_ image: NSImage) {
        saveOverheadImage(image, for: job)
        persistImageReplacementChanges()
    }

    private func replaceCalibrationImageImmediately(_ image: NSImage) {
        saveCalibrationImage(image, for: job)
        persistImageReplacementChanges()
    }

    private func persistImageReplacementChanges() {
        job.updatedAt = Date()
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("Failed to save image replacement: \(error.localizedDescription)")
        }
    }
    
    private func saveOverheadImage(_ image: NSImage, for job: Job) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("overhead_images")
        
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let fileName = "\(job.jobId ?? UUID().uuidString)_overhead.jpg"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            try imageData.write(to: fileURL)
            job.overheadImagePath = fileName
            job.overheadImageFetchedAt = Date()
        } catch {
            print("Failed to save overhead image: \(error.localizedDescription)")
        }
    }
    
    private func saveCalibrationImage(_ image: NSImage, for job: Job) {
        let targetSlot: Int = job.equipmentCalibrationImage1Path != nil ? 1 : (job.equipmentCalibrationImage2Path != nil ? 2 : 1)
        
        let oldSlotPath = targetSlot == 1 ? job.equipmentCalibrationImage1Path : job.equipmentCalibrationImage2Path
        if let oldImagePath = oldSlotPath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let oldImageURL = documentsDirectory.appendingPathComponent("equipment_calibration").appendingPathComponent(oldImagePath)
            do {
                if FileManager.default.fileExists(atPath: oldImageURL.path) {
                    try FileManager.default.removeItem(at: oldImageURL)
                    print("MYDEBUG → Removed old calibration image: \(oldImagePath)")
                }
            } catch {
                print("MYDEBUG → Failed to remove old calibration image: \(error.localizedDescription)")
            }
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("equipment_calibration")
        
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let fileName = "\(job.jobId ?? UUID().uuidString)_calibration_\(targetSlot).jpg"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            try imageData.write(to: fileURL)
            if targetSlot == 1 {
                job.equipmentCalibrationImage1Path = fileName
            } else {
                job.equipmentCalibrationImage2Path = fileName
            }
        } catch {
            print("MYDEBUG → Failed to save calibration image: \(error.localizedDescription)")
        }
    }
}

private struct EditImageSourcePickerSheet: View {
    let title: String
    let onPhotosSelected: () -> Void
    let onFileSelected: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a photo source")
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: onPhotosSelected) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 40))
                        Text("Photos Library")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: onFileSelected) {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 40))
                        Text("Choose File")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

#Preview {
    EditJobView(job: Job(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
