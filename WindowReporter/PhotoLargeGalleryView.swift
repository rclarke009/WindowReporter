//
//  PhotoLargeGalleryView.swift
//  WindowReporter
//
//  macOS version - Large format photo gallery view with date/time stamps and notes
//

import SwiftUI
import CoreData
import AppKit
import Photos

struct PhotoLargeGalleryView: View {
    let window: Window
    let photoType: PhotoType
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [Photo] = []
    @State private var refreshTrigger = UUID()
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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if photosArray.isEmpty {
                    emptyStateView
                } else {
                    photosScrollView
                }
            }
            .navigationTitle("\(photoType.rawValue) Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
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
            
            Text("No photos available for this category.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var photosScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(sortedPhotos, id: \.photoId) { photo in
                    PhotoLargeItemView(
                        photo: photo,
                        dateFormatter: dateFormatter,
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
            print("MYDEBUG → Photo deleted from Core Data")
            refreshPhotos()
        } catch {
            print("MYDEBUG → Failed to delete photo from Core Data: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }
}

struct PhotoLargeItemView: View {
    @ObservedObject var photo: Photo
    let dateFormatter: DateFormatter
    let onDelete: () -> Void
    
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingDetailEdit = false
    @Environment(\.managedObjectContext) private var viewContext
    
    private var photoType: PhotoType {
        if let photoTypeString = photo.photoType {
            return PhotoType(rawValue: photoTypeString) ?? .exterior
        }
        return .exterior
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Photo image with delete button overlay
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    showingDetailEdit = true
                }) {
                    Group {
                        if let image = image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 700)
                        } else if isLoading {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 300)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 300)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        if let error = loadError {
                                            Text(error)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                )
                        }
                    }
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Color.white)
                        .clipShape(Circle())
                        .font(.system(size: 28))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(8)
            }
            
            // Date/time stamp
            if let createdAt = photo.createdAt {
                Text(dateFormatter.string(from: createdAt))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Note text (if exists)
            if let notes = photo.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
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
                    self.loadError = "Failed to load photo"
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
    
    return PhotoLargeGalleryView(window: window, photoType: .exterior)
        .environment(\.managedObjectContext, context)
}
