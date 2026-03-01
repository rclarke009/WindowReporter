//
//  PhotoGalleryView.swift
//  WindowReporter
//
//  macOS version - Photo gallery view matching main app functionality
//

import SwiftUI
import CoreData
import AppKit
import Photos

struct PhotoGalleryView: View {
    let window: Window
    let photoType: PhotoType
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [Photo] = []
    @State private var refreshTrigger = UUID()
    @State private var showingPhotoPicker = false
    @State private var showingDeleteAlert = false
    @State private var photoToDelete: Photo?
    
    private var photosArray: [Photo] {
        let allPhotos = (window.photos?.allObjects as? [Photo]) ?? []
        return allPhotos.filter { photo in
            guard let photoTypeString = photo.photoType else { return false }
            // Check exact match first
            if photoTypeString == photoType.rawValue {
                return true
            }
            // Check if photo type maps to the requested base type
            if let photoTypeEnum = PhotoType(rawValue: photoTypeString) {
                switch (photoTypeEnum, photoType) {
                case (.exterior, .exterior), (.exteriorWideView, .exterior), (.exteriorPhotos, .exterior), (.aama, .exterior):
                    return true
                case (.interior, .interior), (.interiorWideView, .interior), (.interiorCloseup, .interior):
                    return true
                case (.leak, .leak), (.leakCloseups, .leak):
                    return true
                default:
                    return false
                }
            }
            return false
        }
    }
    
    private var sortedPhotos: [Photo] {
        photosArray.sorted(by: { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) })
    }
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if photosArray.isEmpty {
                    emptyStateView
                } else {
                    photosGridView
                }
            }
            .navigationTitle("\(photoType.rawValue) Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingPhotoPicker = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(photoType.color)
                    }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                macOSPhotoPicker(window: window, photoType: photoType, isPresented: $showingPhotoPicker)
            }
            .alert("Delete Photo", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    photoToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let photo = photoToDelete {
                        deletePhoto(photo)
                    }
                    photoToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this photo?")
            }
            .onAppear {
                refreshPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newJobCreated)) { note in
                guard let importedJob = note.object as? Job, let windowJob = window.job else { return }
                if importedJob.objectID == windowJob.objectID {
                    refreshPhotos()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo")
                .font(.system(size: 60))
                .foregroundColor(photoType.color)
            
            Text("No \(photoType.rawValue) Photos")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Click the + button to add your first \(photoType.rawValue.lowercased()) photo.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var photosGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(sortedPhotos, id: \.photoId) { photo in
                    PhotoGalleryThumbnailView(
                        photo: photo,
                        photoType: photoType,
                        onDelete: {
                            photoToDelete = photo
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding()
        }
        .id(refreshTrigger)
    }
    
    private func refreshPhotos() {
        photos = photosArray
        refreshTrigger = UUID()
    }
    
    private func deletePhoto(_ photo: Photo) {
        viewContext.delete(photo)
        
        do {
            try viewContext.save()
            refreshPhotos()
        } catch {
            print("MYDEBUG → Failed to delete photo: \(error.localizedDescription)")
        }
    }
}

struct PhotoGalleryThumbnailView: View {
    @ObservedObject var photo: Photo
    let photoType: PhotoType
    let onDelete: () -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @State private var image: NSImage?
    @State private var showingDetailEdit = false
    @State private var isLoading = true
    
    var body: some View {
        Button(action: {
            showingDetailEdit = true
        }) {
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 200)
                        .clipped()
                        .cornerRadius(8)
                        .rotationEffect(.degrees(photo.rotationDegrees ?? 0))
                } else if isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .overlay(
                            ProgressView()
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                VStack {
                    HStack {
                        // Include in Report indicator
                        if !photo.includeInReport {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.orange)
                                .background(Color.white)
                                .clipShape(Circle())
                                .font(.system(size: 20))
                        }
                        Spacer()
                        Button(action: {
                            onDelete()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
        .sheet(isPresented: $showingDetailEdit) {
            PhotoNoteSelectionView(
                photo: photo,
                photoType: photoType,
                currentNote: photo.notes,
                onNoteSaved: { note in
                    saveNoteToPhoto(photo: photo, note: note)
                },
                onCancel: {
                    showingDetailEdit = false
                }
            )
            .frame(width: 600, height: 700)
        }
    }
    
    private func saveNoteToPhoto(photo: Photo, note: String?) {
        photo.notes = note
        do {
            try viewContext.save()
            showingDetailEdit = false
        } catch {
            print("MYDEBUG → Failed to save note: \(error.localizedDescription)")
        }
    }
    
    private func loadImage() {
        Task {
            let photoService = macOSPhotoImportService(context: viewContext)
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
    let window = Window(context: context)
    window.windowId = "W01"
    window.windowNumber = "W01"
    
    return PhotoGalleryView(window: window, photoType: .exterior)
        .environment(\.managedObjectContext, context)
}
