//
//  macOSPhotoPicker.swift
//  WindowReporter
//
//  macOS photo picker supporting Photos library and file system
//

import SwiftUI
import AppKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct macOSPhotoPicker: View {
    let window: Window
    let photoType: PhotoType
    @Binding var isPresented: Bool
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showingPhotosLibrary = false
    @State private var showingFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var showingNoteSelection = false
    @State private var importedPhoto: Photo?
    
    // Note selection state
    @State private var selectedCategory: PhotoNoteCategory?
    @State private var selectedNote: String?
    @State private var customNoteText: String = ""
    @State private var currentNoteText: String = ""
    
    private let photoImportService: macOSPhotoImportService
    
    init(window: Window, photoType: PhotoType, isPresented: Binding<Bool>) {
        self.window = window
        self.photoType = photoType
        self._isPresented = isPresented
        self.photoImportService = macOSPhotoImportService(context: PersistenceController.shared.container.viewContext)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add \(photoType.rawValue) Photo")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a photo source")
                .font(.body)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                // Photos Library Button
                Button(action: {
                    showingPhotosLibrary = true
                }) {
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
                .buttonStyle(PlainButtonStyle())
                
                // File System Button
                Button(action: {
                    showingFilePicker = true
                }) {
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
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            if isImporting {
                ProgressView("Importing photo...")
                    .padding()
            }
            
            if let error = importError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            if importSuccess && !showingNoteSelection {
                Text("Photo imported successfully!")
                    .foregroundColor(.green)
                    .padding()
            }
            
            if !showingNoteSelection {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
        }
        .frame(width: showingNoteSelection ? 600 : 400, height: showingNoteSelection ? 700 : 300)
        .sheet(isPresented: $showingNoteSelection) {
            if let photo = importedPhoto {
                PhotoNoteSelectionView(
                    photo: photo,
                    photoType: photoType,
                    currentNote: photo.notes,
                    onNoteSaved: { note in
                        saveNoteToPhoto(photo: photo, note: note)
                    },
                    onCancel: {
                        showingNoteSelection = false
                        isPresented = false
                    }
                )
                .frame(width: 600, height: 700)
            }
        }
        .photosPicker(
            isPresented: $showingPhotosLibrary,
            selection: $selectedPhoto,
            matching: .images
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            if let photo = newValue {
                handlePhotosLibraryImport(photo: photo)
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importFromFile(url: url)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
    
    private func handlePhotosLibraryImport(photo: PhotosPickerItem) {
        Task {
            await importFromPhotosLibrary(photo: photo)
        }
    }
    
    private func importFromFile(url: URL) async {
        isImporting = true
        importError = nil
        importSuccess = false
        
        do {
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "PhotoImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let photo = try await photoImportService.importFromFile(url: url, window: window, photoType: photoType)
            
            await MainActor.run {
                isImporting = false
                importSuccess = true
                importedPhoto = photo
                // Show note selection instead of auto-dismissing
                showingNoteSelection = true
            }
        } catch {
            await MainActor.run {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }
    
    private func importFromPhotosLibrary(photo: PhotosPickerItem) async {
        isImporting = true
        importError = nil
        importSuccess = false
        
        do {
            // Load image data from PhotosPickerItem
            guard let imageData = try await photo.loadTransferable(type: Data.self),
                  let nsImage = NSImage(data: imageData) else {
                await MainActor.run {
                    isImporting = false
                    importError = "Failed to load image from Photos library"
                }
                return
            }
            
            // Save to temporary location and import as file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                await MainActor.run {
                    isImporting = false
                    importError = "Failed to convert image"
                }
                return
            }
            
            try jpegData.write(to: tempURL)
            
            // Import as file (which will copy to app's directory)
            let photo = try await photoImportService.importFromFile(url: tempURL, window: window, photoType: photoType)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            await MainActor.run {
                isImporting = false
                importSuccess = true
                importedPhoto = photo
                // Show note selection instead of auto-dismissing
                showingNoteSelection = true
            }
        } catch {
            await MainActor.run {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }
    
    private func saveNoteToPhoto(photo: Photo, note: String?) {
        photo.notes = note
        do {
            try viewContext.save()
            showingNoteSelection = false
            isPresented = false
        } catch {
            print("Failed to save note: \(error.localizedDescription)")
        }
    }
}

// MARK: - Photo Note Selection View
struct PhotoNoteSelectionView: View {
    let photo: Photo
    let photoType: PhotoType
    let currentNote: String?
    let onNoteSaved: (String?) -> Void
    let onCancel: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedCategory: PhotoNoteCategory?
    @State private var selectedNote: String?
    @State private var customNoteText: String = ""
    @State private var currentNoteText: String = ""
    @State private var photoImage: NSImage?
    @State private var isLoadingPhoto = true
    @State private var photoLoadError: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView {
                    VStack(spacing: 20) {
                        // Photo preview at top
                        photoPreviewView
                        
                        // Current Note field - always visible
                        currentNoteFieldView
                        
                        // Category or note selection
                        if selectedCategory == nil {
                            categorySelectionView
                        } else {
                            noteSelectionView
                        }
                    }
                    .padding(.top)
                }
                
                // Fixed buttons at bottom
                actionButtonsView
            }
            .navigationTitle("Edit Photo Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .onAppear {
                // Load photo image
                loadPhotoImage()
                
                // Initialize currentNoteText with currentNote
                currentNoteText = currentNote ?? ""
                
                // Pre-select category if current note matches a predefined option
                if let note = currentNote, !note.isEmpty {
                    let categories = PhotoNoteCategories.getCategories(for: photoType).filter { $0.name != "Custom/Other" }
                    for category in categories {
                        if category.options.contains(note) {
                            selectedCategory = category
                            selectedNote = note
                            currentNoteText = note
                            break
                        }
                    }
                // If no match found, it's a custom note - don't pre-select any category
                // User can select any category and use the custom note option
            }
        }
        .frame(width: 600, height: 700)
    }
    
    private var photoPreviewView: some View {
        VStack(spacing: 8) {
            if let image = photoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else if isLoadingPhoto {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading photo...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            } else if let error = photoLoadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Failed to load photo")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Photo not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            }
        }
        .padding(.horizontal)
    }
    
    private func loadPhotoImage() {
        print("MYDEBUG → PhotoNoteSelectionView - loadPhotoImage() called")
        print("MYDEBUG → PhotoNoteSelectionView - Photo ID: \(photo.photoId ?? "nil")")
        print("MYDEBUG → PhotoNoteSelectionView - Photo source: \(photo.photoSource ?? "nil")")
        print("MYDEBUG → PhotoNoteSelectionView - Photo localIdentifier: \(photo.localIdentifier ?? "nil")")
        print("MYDEBUG → PhotoNoteSelectionView - Photo filePath: \(photo.filePath ?? "nil")")
        
        isLoadingPhoto = true
        photoLoadError = nil
        
        Task {
            let photoService = macOSPhotoImportService(context: viewContext)
            if let loadedImage = await photoService.getImage(for: photo) {
                await MainActor.run {
                    print("MYDEBUG → PhotoNoteSelectionView - Photo loaded successfully, size: \(loadedImage.size)")
                    self.photoImage = loadedImage
                    self.isLoadingPhoto = false
                }
            } else {
                await MainActor.run {
                    print("MYDEBUG → PhotoNoteSelectionView - Failed to load photo")
                    self.photoLoadError = "Could not load photo image"
                    self.isLoadingPhoto = false
                }
            }
        }
    }
    
    private var currentNoteFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Note")
                .font(.headline)
                .padding(.horizontal)
            
            ZStack(alignment: .topLeading) {
                if currentNoteText.isEmpty {
                    Text("note - example This image shows a crack next to the sill")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                
                TextEditor(text: $currentNoteText)
                    .frame(minHeight: 80)
                    .padding(4)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(currentNoteText.isEmpty ? Color.clear : Color.blue, lineWidth: 2)
                    )
            }
            .padding(.horizontal)
        }
    }
    
    private var categorySelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Note Category")
                .font(.headline)
                .padding(.horizontal)
            
            let allCategoryNames = PhotoNoteCategories.getAllCategoryNames(for: photoType)
            let categoryNames = allCategoryNames.filter { $0 != "Custom/Other" }
            
            if categoryNames.isEmpty {
                Text("No categories available")
                    .foregroundColor(.red)
                    .padding()
            } else {
                VStack(spacing: 10) {
                    ForEach(categoryNames, id: \.self) { categoryName in
                        Button(action: {
                            if let category = PhotoNoteCategories.getCategory(byName: categoryName, for: photoType) {
                                selectedCategory = category
                                // Pre-select current note if it matches an option in this category
                                if let note = currentNote, category.options.contains(note) {
                                    selectedNote = note
                                    currentNoteText = note
                                }
                            }
                        }) {
                            HStack {
                                Text(categoryName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var noteSelectionView: some View {
        if let category = selectedCategory {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: {
                        selectedCategory = nil
                        selectedNote = nil
                        customNoteText = ""
                        // Don't clear currentNoteText - keep it for editing
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                    }
                    
                    Text(category.name)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                
                if category.name == "Custom/Other" {
                    // Custom text input - sync with currentNoteText
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter custom note:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        TextEditor(text: Binding(
                            get: { customNoteText },
                            set: { newValue in
                                customNoteText = newValue
                                currentNoteText = newValue
                            }
                        ))
                            .frame(height: 200)
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .onAppear {
                                // Initialize customNoteText from currentNoteText if it exists
                                if !currentNoteText.isEmpty && customNoteText.isEmpty {
                                    customNoteText = currentNoteText
                                }
                            }
                    }
                } else {
                    // Predefined note options
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(category.options, id: \.self) { option in
                                Button(action: {
                                    selectedNote = option
                                    // Populate current note field with selected option
                                    currentNoteText = option
                                    // Clear custom text when selecting a predefined option
                                    if !customNoteText.isEmpty {
                                        customNoteText = ""
                                    }
                                }) {
                                    HStack {
                                        Text(option)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        if selectedNote == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding()
                                    .background(selectedNote == option ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            // Always show Save Note button if there's any note text
            if !currentNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: {
                    // Use currentNoteText as the primary source
                    let trimmedNote = currentNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let note: String? = trimmedNote.isEmpty ? nil : trimmedNote
                    onNoteSaved(note)
                }) {
                    Text("Save Note")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            
            Button(action: {
                onNoteSaved(nil)
            }) {
                Text("Skip Note")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, 8)
        .background(Color(.windowBackgroundColor))
    }
}

