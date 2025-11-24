//
//  CreateJobView.swift
//  WindowReporter
//
//  macOS version
//

import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

struct CreateJobView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("inspectorName") private var settingsInspectorName: String = ""
    
    @State private var jobId: String = ""
    @State private var clientName: String = ""
    @State private var addressLine1: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""
    @State private var notes: String = ""
    @State private var inspectorName: String = ""
    @State private var inspectionDate: Date = Date()
    @State private var overheadImageSourceName: String = ""
    @State private var overheadImageSourceUrl: String = ""
    @State private var scalePixelsPerFoot: String = "10.0"
    
    @State private var selectedOverheadImage: NSImage?
    @State private var selectedFrontOfHomeImage: NSImage?
    @State private var showingOverheadImagePicker = false
    @State private var showingFrontOfHomeImagePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Job Information") {
                    TextField("Report ID", text: $jobId, prompt: Text("W2025-11001"))
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
                }
                
                Section("Inspector Information") {
                    TextField("Inspector Name", text: $inspectorName)
                    DatePicker("Inspection Date", selection: $inspectionDate, displayedComponents: .date)
                }
                
                Section("Overhead Image") {
                    Button(action: {
                        showingOverheadImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            if selectedOverheadImage != nil {
                                Text("Overhead Image Selected")
                                    .foregroundColor(.green)
                            } else {
                                Text("Select Overhead Image")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if let image = selectedOverheadImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                }
                
                Section("Front of Home Image") {
                    Button(action: {
                        showingFrontOfHomeImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            if selectedFrontOfHomeImage != nil {
                                Text("Front of Home Image Selected")
                                    .foregroundColor(.green)
                            } else {
                                Text("Select Front of Home Image")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if let image = selectedFrontOfHomeImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                }
                
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report ID: \(jobId.isEmpty ? "Not specified" : jobId)")
                        Text("Client: \(clientName.isEmpty ? "Not specified" : clientName)")
                        Text("Address: \(addressLine1.isEmpty ? "Not specified" : addressLine1), \(city.isEmpty ? "City" : city), \(state.isEmpty ? "ST" : state) \(zip.isEmpty ? "00000" : zip)")
                        Text("Inspector: \(inspectorName.isEmpty ? "Not specified" : inspectorName)")
                        Text("Date: \(inspectionDate, formatter: dateFormatter)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Create New Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createJob()
                    }
                    .disabled(!isFormValid)
                }
            }
            .fileImporter(
                isPresented: $showingOverheadImagePicker,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                handleImageSelection(result: result, isOverhead: true)
            }
            .fileImporter(
                isPresented: $showingFrontOfHomeImagePicker,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                handleImageSelection(result: result, isOverhead: false)
            }
            .alert("Job Created", isPresented: $showingAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if inspectorName.isEmpty && !settingsInspectorName.isEmpty {
                    inspectorName = settingsInspectorName
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !jobId.isEmpty && !clientName.isEmpty && !addressLine1.isEmpty && !city.isEmpty && !state.isEmpty && !zip.isEmpty
    }
    
    private func handleImageSelection(result: Result<[URL], Error>, isOverhead: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if let image = NSImage(contentsOf: url) {
                if isOverhead {
                    selectedOverheadImage = image
                } else {
                    selectedFrontOfHomeImage = image
                }
            }
        case .failure:
            break
        }
    }
    
    private func createJob() {
        let newJob = Job(context: viewContext)
        newJob.jobId = jobId
        newJob.clientName = clientName
        newJob.addressLine1 = addressLine1
        newJob.cleanedAddressLine1 = AddressCleaningUtility.cleanAddress(addressLine1)
        newJob.city = city
        newJob.state = state
        newJob.zip = zip
        newJob.notes = notes.isEmpty ? nil : notes
        newJob.inspectorName = inspectorName.isEmpty ? nil : inspectorName
        newJob.inspectionDate = inspectionDate
        newJob.status = "Ready"
        newJob.testProcedure = "ASTM E331"
        newJob.waterPressure = 12.0
        newJob.createdAt = Date()
        newJob.updatedAt = Date()
        newJob.overheadImageSourceName = overheadImageSourceName.isEmpty ? nil : overheadImageSourceName
        newJob.overheadImageSourceUrl = overheadImageSourceUrl.isEmpty ? nil : overheadImageSourceUrl
        newJob.scalePixelsPerFoot = Double(scalePixelsPerFoot) ?? 10.0
        
        if let image = selectedOverheadImage {
            saveOverheadImage(image, for: newJob)
        }
        
        if let image = selectedFrontOfHomeImage {
            saveFrontOfHomeImage(image, for: newJob)
        }
        
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .newJobCreated, object: newJob)
            alertMessage = "Job '\(jobId)' created successfully!"
            showingAlert = true
        } catch {
            alertMessage = "Failed to create job: \(error.localizedDescription)"
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
    
    private func saveFrontOfHomeImage(_ image: NSImage, for job: Job) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("front_of_home_images")
        
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let fileName = "\(job.jobId ?? UUID().uuidString)_front_of_home.jpg"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            try imageData.write(to: fileURL)
            job.frontOfHomeImagePath = fileName
        } catch {
            print("Failed to save front of home image: \(error.localizedDescription)")
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

#Preview {
    CreateJobView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

