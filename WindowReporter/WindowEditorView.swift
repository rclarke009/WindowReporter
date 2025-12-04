//
//  WindowEditorView.swift
//  WindowReporter
//
//  macOS version - Window detail editor
//

import SwiftUI
import CoreData
import AppKit

struct WindowEditorView: View {
    @ObservedObject var window: Window
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var windowNumber: String
    @State private var windowType: String
    @State private var material: String
    @State private var testResult: String
    @State private var leakPoints: Int16
    @State private var isInaccessible: Bool
    @State private var notes: String
    @State private var widthString: String
    @State private var heightString: String
    @State private var showingPhotoPicker: PhotoType?
    @State private var activePhotoGallery: PhotoType?
    
    private let materialOptions = ["Aluminum", "Metal", "Vinyl", "Wood", "Unknown"]
    
    init(window: Window) {
        self.window = window
        _windowNumber = State(initialValue: window.windowNumber ?? "")
        _windowType = State(initialValue: window.windowType ?? "")
        _material = State(initialValue: window.material ?? "Aluminum")
        _testResult = State(initialValue: window.testResult ?? "")
        _leakPoints = State(initialValue: window.leakPoints)
        _isInaccessible = State(initialValue: window.isInaccessible)
        _notes = State(initialValue: window.notes ?? "")
        _widthString = State(initialValue: window.width > 0 ? String(format: "%.0f", window.width) : "")
        _heightString = State(initialValue: window.height > 0 ? String(format: "%.0f", window.height) : "")
    }
    
    private var photos: [Photo] {
        guard let photosSet = window.photos else { return [] }
        return (photosSet.allObjects as? [Photo] ?? []).sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Window Details") {
                    TextField("Window Number", text: $windowNumber)
                    
                    TextField("Window Type", text: $windowType)
                    
                    Picker("Material", selection: $material) {
                        ForEach(materialOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
                
                Section("Measurements") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Width (inches)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Width", text: $widthString)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Height (inches)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Height", text: $heightString)
                        }
                    }
                }
                
                Section("Test Results") {
                    Picker("Test Result", selection: $testResult) {
                        Text("Pending").tag("")
                        Text("Pass").tag("Pass")
                        Text("Fail").tag("Fail")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Toggle("Not Tested", isOn: $isInaccessible)
                    
                    Stepper("Leak Points: \(leakPoints)", value: $leakPoints, in: 0...100)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
                
                Section("Photos") {
                    // Photo type buttons
                    HStack(spacing: 12) {
                        ForEach([PhotoType.exterior, PhotoType.interior, PhotoType.leak], id: \.self) { photoType in
                            Button(action: {
                                showingPhotoPicker = photoType
                            }) {
                                VStack {
                                    Image(systemName: photoType.icon)
                                        .font(.title2)
                                    Text(photoType.rawValue.capitalized)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Photo galleries by type
                    ForEach([PhotoType.exterior, PhotoType.interior, PhotoType.leak], id: \.self) { photoType in
                        let typePhotos = photos.filter { $0.photoType == photoType.rawValue }
                        if !typePhotos.isEmpty {
                            DisclosureGroup("\(photoType.rawValue.capitalized) Photos (\(typePhotos.count))") {
                                ScrollView(.horizontal, showsIndicators: true) {
                                    HStack(spacing: 12) {
                                        ForEach(typePhotos, id: \.objectID) { photo in
                                            PhotoThumbnailView(photo: photo)
                                        }
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                }
                
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Cancel")
                                .frame(minWidth: 100)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            saveWindow()
                        }) {
                            Text("Save")
                                .frame(minWidth: 100)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 800, idealWidth: 1000, maxWidth: .infinity, minHeight: 600, idealHeight: 800, maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle("Window \(windowNumber.isEmpty ? "?" : windowNumber)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWindow()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .sheet(item: $showingPhotoPicker) { photoType in
                macOSPhotoPicker(window: window, photoType: photoType, isPresented: Binding(
                    get: { showingPhotoPicker != nil },
                    set: { if !$0 { showingPhotoPicker = nil } }
                ))
            }
        }
    }
    
    private func saveWindow() {
        window.windowNumber = windowNumber.isEmpty ? nil : windowNumber
        window.windowType = windowType.isEmpty ? nil : windowType
        window.material = material
        window.testResult = testResult.isEmpty ? nil : testResult
        window.leakPoints = leakPoints
        window.isInaccessible = isInaccessible
        window.notes = notes.isEmpty ? nil : notes
        
        if let width = Double(widthString) {
            window.width = width
        }
        if let height = Double(heightString) {
            window.height = height
        }
        
        window.updatedAt = Date()
        
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: nil)
            dismiss()
        } catch {
            print("Failed to save window: \(error)")
        }
    }
}

struct PhotoThumbnailView: View {
    @ObservedObject var photo: Photo
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var showingNoteEditor = false
    @Environment(\.managedObjectContext) private var viewContext
    
    // Get photoType from photo object
    private var photoType: PhotoType {
        if let photoTypeString = photo.photoType {
            return PhotoType(rawValue: photoTypeString) ?? .exterior
        }
        return .exterior
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if isLoading {
                ProgressView()
                    .frame(width: 150, height: 150)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .frame(width: 150, height: 150)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            if let notes = photo.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(width: 150)
            } else {
                Text("Tap to add note")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 150)
            }
        }
        .onTapGesture {
            showingNoteEditor = true
        }
        .onAppear {
            loadImage()
        }
        .sheet(isPresented: $showingNoteEditor) {
            PhotoNoteSelectionView(
                photo: photo,
                photoType: photoType,
                currentNote: photo.notes,
                onNoteSaved: { note in
                    saveNoteToPhoto(photo: photo, note: note)
                },
                onCancel: {
                    showingNoteEditor = false
                }
            )
            .frame(width: 600, height: 700)
        }
    }
    
    private func saveNoteToPhoto(photo: Photo, note: String?) {
        photo.notes = note
        do {
            try viewContext.save()
            showingNoteEditor = false
        } catch {
            print("Failed to save note: \(error.localizedDescription)")
        }
    }
    
    private func loadImage() {
        Task {
            let photoService = macOSPhotoImportService(context: PersistenceController.shared.container.viewContext)
            if let loadedImage = await photoService.getImage(for: photo) {
                await MainActor.run {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let job = Job(context: context)
    job.jobId = "TEST-123"
    let window = Window(context: context)
    window.windowId = UUID().uuidString
    window.windowNumber = "1"
    window.job = job
    
    return WindowEditorView(window: window)
        .environment(\.managedObjectContext, context)
}

