//
//  ReporterSectionPhotoGalleryView.swift
//  WindowReporter
//
//  Section photos: add from file or Photos, grid + delete.
//

import SwiftUI
import CoreData
import AppKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct ReporterSectionPhotoGalleryView: View {
    let section: SpecimenSection
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTrigger = UUID()
    @State private var showingDeleteAlert = false
    @State private var photoToDelete: SectionPhoto?
    @State private var showingFileImporter = false
    @State private var photosPickerItem: PhotosPickerItem?

    private var photosArray: [SectionPhoto] {
        let all = (section.sectionPhotos?.allObjects as? [SectionPhoto]) ?? []
        return all.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
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
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(photosArray, id: \.photoId) { photo in
                                ReporterSectionPhotoThumbCell(
                                    photo: photo,
                                    onDelete: {
                                        photoToDelete = photo
                                        showingDeleteAlert = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Section Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Choose File…") { showingFileImporter = true }
                        PhotosPicker("Photos Library…", selection: $photosPickerItem, matching: .images)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .jpeg, .png, .heic], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importImageFile(url: url)
                    }
                case .failure(let err):
                    print("MYDEBUG →", "Section photo file import failed: \(err)")
                }
            }
            .onChange(of: photosPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await importPhotosPickerItem(newItem)
                    await MainActor.run { photosPickerItem = nil }
                }
            }
            .alert("Delete Photo", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { photoToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let p = photoToDelete {
                        deletePhoto(p)
                    }
                    photoToDelete = nil
                }
            } message: {
                Text("Remove this photo from the section?")
            }
            .id(refreshTrigger)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No photos yet")
                .foregroundColor(.secondary)
            HStack {
                Button("Add from File") { showingFileImporter = true }
                PhotosPicker("Photos Library", selection: $photosPickerItem, matching: .images)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importImageFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("MYDEBUG →", "Could not access scoped file for section photo")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let job = section.job, let jobId = job.jobId, let sectionId = section.sectionId else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destDir = docs
            .appendingPathComponent("photos")
            .appendingPathComponent(jobId)
            .appendingPathComponent("section")
            .appendingPathComponent(sectionId)
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let name = "\(UUID().uuidString).\(ext)"
            let dest = destDir.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: dest)
            let rel = "photos/\(jobId)/section/\(sectionId)/\(name)"
            let sp = SectionPhoto(context: viewContext)
            sp.photoId = UUID().uuidString
            sp.photoType = "Specimen"
            sp.filePath = rel
            sp.photoSource = "FileSystem"
            sp.includeInReport = true
            sp.createdAt = Date()
            sp.specimenSection = section
            try viewContext.save()
            print("MYDEBUG →", "Section photo added: \(rel)")
            refreshTrigger = UUID()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Section photo import error: \(error)")
        }
    }

    private func importPhotosPickerItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let job = section.job, let jobId = job.jobId, let sectionId = section.sectionId else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destDir = docs
            .appendingPathComponent("photos")
            .appendingPathComponent(jobId)
            .appendingPathComponent("section")
            .appendingPathComponent(sectionId)
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).jpg"
            let dest = destDir.appendingPathComponent(name)
            try data.write(to: dest)
            let rel = "photos/\(jobId)/section/\(sectionId)/\(name)"
            await MainActor.run {
                let sp = SectionPhoto(context: viewContext)
                sp.photoId = UUID().uuidString
                sp.photoType = "Specimen"
                sp.filePath = rel
                sp.photoSource = "FileSystem"
                sp.includeInReport = true
                sp.createdAt = Date()
                sp.specimenSection = section
                try? viewContext.save()
                print("MYDEBUG →", "Section photo from picker: \(rel)")
                refreshTrigger = UUID()
                NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            }
        } catch {
            print("MYDEBUG →", "PhotosPicker import failed: \(error)")
        }
    }

    private func deletePhoto(_ photo: SectionPhoto) {
        if let rel = photo.filePath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = docs.appendingPathComponent(rel)
            try? FileManager.default.removeItem(at: url)
        }
        viewContext.delete(photo)
        try? viewContext.save()
        refreshTrigger = UUID()
        if let job = section.job {
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        }
    }
}

private struct ReporterSectionPhotoThumbCell: View {
    let photo: SectionPhoto
    var onDelete: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }
            }
            .frame(width: 120, height: 120)
            .clipped()
            .cornerRadius(8)

            Text((photo.notes?.isEmpty == false) ? (photo.notes ?? "") : (photo.photoType ?? ""))
                .font(.caption2)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .task(id: photo.photoId) {
            image = await loadThumbAsync(for: photo)
        }
    }

    private func loadThumbAsync(for photo: SectionPhoto) async -> NSImage? {
        if photo.photoSource == "FileSystem", let rel = photo.filePath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = docs.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                return NSImage(contentsOfFile: url.path)
            }
        }
        if let id = photo.localIdentifier, !id.isEmpty {
            return await withCheckedContinuation { cont in
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                guard let asset = assets.firstObject else {
                    cont.resume(returning: nil)
                    return
                }
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFill, options: nil) { img, _ in
                    cont.resume(returning: img)
                }
            }
        }
        return nil
    }
}
