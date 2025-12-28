//
//  EditJobView.swift
//  WindowReporter
//
//  macOS version
//

import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

struct EditJobView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let job: Job
    
    @State private var jobId: String
    @State private var clientName: String
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
    
    @State private var showingImagePicker = false
    @State private var selectedImage: NSImage?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let statusOptions = ["Ready", "In Progress", "Completed", "Failed"]
    
    init(job: Job) {
        self.job = job
        _jobId = State(initialValue: job.jobId ?? "")
        _clientName = State(initialValue: job.clientName ?? "")
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
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Job Information") {
                    TextField("Job ID", text: $jobId)
                    TextField("Client Name", text: $clientName)
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
                    HStack {
                        Text("Water Pressure")
                        Spacer()
                        TextField("PSI", text: $waterPressure)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("PSI")
                            .foregroundColor(.secondary)
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
                        }
                    }
                    
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            if selectedImage != nil {
                                Text("New Image Selected")
                                    .foregroundColor(.green)
                            } else {
                                Text(job.overheadImagePath != nil ? "Replace Image" : "Select Overhead Image")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if let image = selectedImage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Image")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .cornerRadius(8)
                        }
                    }
                }
            }
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
                selectedImage = image
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
    
    private func saveJob() {
        job.jobId = jobId
        job.clientName = clientName
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
        job.updatedAt = Date()
        
        if let image = selectedImage {
            saveOverheadImage(image, for: job)
        }
        
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
}

#Preview {
    EditJobView(job: Job(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

