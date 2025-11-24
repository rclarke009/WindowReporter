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
            
            if importSuccess {
                Text("Photo imported successfully!")
                    .foregroundColor(.green)
                    .padding()
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
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
            
            _ = try await photoImportService.importFromFile(url: url, window: window, photoType: photoType)
            
            await MainActor.run {
                isImporting = false
                importSuccess = true
                // Auto-dismiss after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isPresented = false
                }
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
            _ = try await photoImportService.importFromFile(url: tempURL, window: window, photoType: photoType)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            await MainActor.run {
                isImporting = false
                importSuccess = true
                // Auto-dismiss after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isPresented = false
                }
            }
        } catch {
            await MainActor.run {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }
}

