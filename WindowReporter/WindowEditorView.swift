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
    @State private var isInaccessible: Bool
    @State private var notes: String
    @State private var widthString: String
    @State private var heightString: String
    @State private var showingPhotoPicker: PhotoType?
    @State private var activePhotoGallery: PhotoType?
    @State private var activeLargePhotoGallery: PhotoType?
    @State private var untestedReason: String?
    @State private var selectedReasonType: String = "Inaccessible"
    @State private var customReason: String = ""
    @State private var showingReasonSelectionSheet = false
    @State private var showingLocationMarker = false
    /// Photo Thumbnails section: expanded by default for quick-glance gallery (exterior, interior, leak).
    @State private var expandedPhotoThumbnailTypes: Set<PhotoType> = [.exterior, .interior, .leak]
    
    private let materialOptions = ["Aluminum", "Metal", "Vinyl", "Wood", "Unknown"]
    
    init(window: Window) {
        self.window = window
        _windowNumber = State(initialValue: window.windowNumber ?? "")
        _windowType = State(initialValue: window.windowType ?? "")
        _material = State(initialValue: window.material ?? "Aluminum")
        _testResult = State(initialValue: window.testResult ?? "")
        _isInaccessible = State(initialValue: window.isInaccessible)
        _notes = State(initialValue: window.notes ?? "")
        _widthString = State(initialValue: window.width > 0 ? String(format: "%.0f", window.width) : "")
        _heightString = State(initialValue: window.height > 0 ? String(format: "%.0f", window.height) : "")
        
        let existingReason = window.untestedReason
        _untestedReason = State(initialValue: existingReason)
        if let reason = existingReason {
            if reason == "Inaccessible" {
                _selectedReasonType = State(initialValue: "Inaccessible")
            } else if reason == "Damaged so that it would not close properly." {
                _selectedReasonType = State(initialValue: "Damaged so that it would not close properly.")
            } else if reason == "Windows with air conditioning units installed cannot be tested, as the presence of the unit prevents proper sealing of the window assembly. This compromises the integrity of the test conditions, rendering the results invalid." {
                _selectedReasonType = State(initialValue: "Windows with air conditioning units installed cannot be tested, as the presence of the unit prevents proper sealing of the window assembly. This compromises the integrity of the test conditions, rendering the results invalid.")
            } else if reason == "Window was blocked by items that were not movable." {
                _selectedReasonType = State(initialValue: "Window was blocked by items that were not movable.")
            } else if reason == "Did not have access to window because of locked door." {
                _selectedReasonType = State(initialValue: "Did not have access to window because of locked door.")
            } else {
                _selectedReasonType = State(initialValue: "Other/Custom")
                _customReason = State(initialValue: reason)
            }
        } else {
            _selectedReasonType = State(initialValue: "Inaccessible")
        }
    }
    
    private var displayReasonText: String {
        if selectedReasonType == "Other/Custom" && !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customReason
        }
        return selectedReasonType
    }
    
    private func syncUntestedReasonFromSelection() {
        if selectedReasonType == "Other/Custom" {
            let trimmed = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
            untestedReason = trimmed.isEmpty ? nil : trimmed
        } else {
            untestedReason = selectedReasonType
        }
    }
    
    private func expandedBinding(for photoType: PhotoType) -> Binding<Bool> {
        Binding(
            get: { expandedPhotoThumbnailTypes.contains(photoType) },
            set: { if $0 { expandedPhotoThumbnailTypes.insert(photoType) } else { expandedPhotoThumbnailTypes.remove(photoType) } }
        )
    }
    
    private var photos: [Photo] {
        guard let photosSet = window.photos else {
            print("MYDEBUG → WindowEditorView - window.photos is nil")
            return []
        }
        let allPhotos = (photosSet.allObjects as? [Photo] ?? [])
        print("MYDEBUG → WindowEditorView - Found \(allPhotos.count) photos for window \(window.windowNumber ?? "nil")")
        for photo in allPhotos {
            print("MYDEBUG →   Photo: ID=\(photo.photoId ?? "nil"), Type=\(photo.photoType ?? "nil"), Created=\(photo.createdAt?.description ?? "nil")")
        }
        return allPhotos.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }
    
    // Helper function to get base photo type for filtering
    private func getBasePhotoType(for photoTypeString: String?) -> PhotoType {
        guard let photoTypeString = photoTypeString else { return .exterior }
        if let photoType = PhotoType(rawValue: photoTypeString) {
            // Map specific types to base categories
            switch photoType {
            case .exterior, .exteriorWideView, .exteriorPhotos, .aama:
                return .exterior
            case .interior, .interiorWideView, .interiorCloseup:
                return .interior
            case .leak, .leakCloseups:
                return .leak
            }
        }
        return .exterior
    }
    
    // Helper function to filter photos by base type
    private func photos(for baseType: PhotoType) -> [Photo] {
        return photos.filter { photo in
            let baseTypeForPhoto = getBasePhotoType(for: photo.photoType)
            return baseTypeForPhoto == baseType
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Window Details") {
                    TextField("Window Number", text: $windowNumber)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Window Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ReporterWindowTypePickerView(selectedWindowType: $windowType)
                    }
                    
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
                
                Section("Location") {
                    Button(action: {
                        showingLocationMarker = true
                    }) {
                        HStack {
                            Image(systemName: (window.xPosition > 0 && window.yPosition > 0) ? "checkmark.square.fill" : "square")
                                .foregroundColor((window.xPosition > 0 && window.yPosition > 0) ? .blue : .secondary)
                                .font(.system(size: 20))
                            Text((window.xPosition > 0 && window.yPosition > 0) ? "Location Marked" : "Mark Location on Overhead")
                                .foregroundColor((window.xPosition > 0 && window.yPosition > 0) ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                }
                
                Section("Test Results") {
                    Picker("Test Result", selection: $testResult) {
                        Text("Pending").tag("")
                        Text("Pass").tag("Pass")
                        Text("Fail").tag("Fail")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Toggle("Not Tested", isOn: $isInaccessible)
                    
                    if isInaccessible {
                        Button(action: {
                            showingReasonSelectionSheet = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reason")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(displayReasonText)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
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
                }
                
                // Photo Galleries - Visual buttons
                Section("Photo Galleries") {
                    ForEach([PhotoType.exterior, PhotoType.interior, PhotoType.leak], id: \.self) { photoType in
                        let typePhotos = photos(for: photoType)
                        PhotoGalleryButtonRow(
                            photoType: photoType,
                            photoCount: typePhotos.count,
                            onGridTap: {
                                activePhotoGallery = photoType
                            },
                            onLargeTap: {
                                activeLargePhotoGallery = photoType
                            }
                        )
                    }
                }
                .onAppear {
                    print("MYDEBUG → WindowEditorView - Photo Galleries section appeared")
                    print("MYDEBUG → Total photos: \(photos.count)")
                    for photoType in PhotoType.allCases {
                        let typePhotos = photos.filter { $0.photoType == photoType.rawValue }
                        print("MYDEBUG → \(photoType.rawValue) photos: \(typePhotos.count)")
                    }
                    // Also log by base categories
                    print("MYDEBUG → Base categories:")
                    print("MYDEBUG →   Exterior (base): \(photos(for: .exterior).count)")
                    print("MYDEBUG →   Interior (base): \(photos(for: .interior).count)")
                    print("MYDEBUG →   Leak (base): \(photos(for: .leak).count)")
                }
                
                Section("Photo Thumbnails") {
                    // Photo galleries by type (thumbnail preview); expanded by default for quick-glance gallery
                    ForEach([PhotoType.exterior, PhotoType.interior, PhotoType.leak], id: \.self) { photoType in
                        let typePhotos = photos(for: photoType)
                        if !typePhotos.isEmpty {
                            DisclosureGroup(isExpanded: expandedBinding(for: photoType)) {
                                ScrollView(.horizontal, showsIndicators: true) {
                                    HStack(spacing: 12) {
                                        ForEach(typePhotos, id: \.objectID) { photo in
                                            PhotoThumbnailView(photo: photo)
                                        }
                                    }
                                    .padding()
                                }
                            } label: {
                                Text("\(photoType.rawValue.capitalized) Photos (\(typePhotos.count))")
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
            .sheet(item: $activePhotoGallery) { photoType in
                PhotoGalleryView(window: window, photoType: photoType)
                    .frame(width: 1000, height: 800)
            }
            .sheet(item: $activeLargePhotoGallery) { photoType in
                PhotoLargeGalleryView(window: window, photoType: photoType)
                    .frame(width: 800, height: 600)
            }
            .sheet(isPresented: $showingReasonSelectionSheet) {
                UntestedReasonSelectionView(
                    selectedReason: $selectedReasonType,
                    customReason: $customReason,
                    onDismiss: {
                        showingReasonSelectionSheet = false
                        syncUntestedReasonFromSelection()
                    }
                )
            }
            .sheet(isPresented: $showingLocationMarker) {
                LocationMarkerView(window: window)
                    .frame(minWidth: 500, minHeight: 500)
            }
        }
    }
    
    private func saveWindow() {
        window.windowNumber = windowNumber.isEmpty ? nil : windowNumber
        window.windowType = windowType.isEmpty ? nil : windowType
        window.material = material
        window.testResult = testResult.isEmpty ? nil : testResult
        window.isInaccessible = isInaccessible
        let reasonToSave: String? = isInaccessible ? (untestedReason ?? (selectedReasonType == "Other/Custom" ? nil : selectedReasonType)) : nil
        window.untestedReason = reasonToSave
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

struct PhotoGalleryButtonRow: View {
    let photoType: PhotoType
    let photoCount: Int
    let onGridTap: () -> Void
    let onLargeTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: photoType.icon)
                .font(.title2)
                .foregroundColor(photoType.color)
                .frame(width: 30)
            
            // Photo type name
            Text("\(photoType.rawValue) Photos")
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            // Photo count badge
            HStack(spacing: 4) {
                Text("\(photoCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "photo.fill")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Grid View button
            Button(action: {
                print("MYDEBUG → PhotoGalleryButtonRow - Grid button tapped for \(photoType.rawValue)")
                onGridTap()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3")
                        .font(.caption)
                    Text("Grid")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(photoCount > 0 ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(photoCount > 0 ? photoType.color : Color.gray.opacity(0.3))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(photoCount == 0)
            
            // Large View button
            Button(action: {
                print("MYDEBUG → PhotoGalleryButtonRow - Large button tapped for \(photoType.rawValue)")
                onLargeTap()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack")
                        .font(.caption)
                    Text("Large")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(photoCount > 0 ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(photoCount > 0 ? photoType.color.opacity(0.8) : Color.gray.opacity(0.3))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(photoCount == 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onAppear {
            print("MYDEBUG → PhotoGalleryButtonRow appeared for \(photoType.rawValue) with \(photoCount) photos")
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
    window.displayOrder = 0
    window.job = job
    
    return WindowEditorView(window: window)
        .environment(\.managedObjectContext, context)
}

