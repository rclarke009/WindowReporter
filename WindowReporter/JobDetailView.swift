//
//  JobDetailView.swift
//  WindowReporter
//
//  macOS version - basic structure
//

import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers
import PhotosUI

/// Get the pixel dimensions of an NSImage for use as canonical coordinate space (matches PDF/cgImage).
func overheadImagePixelSize(_ image: NSImage) -> CGSize {
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return CGSize(width: cg.width, height: cg.height)
    }
    if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
        return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
    return image.size
}

/// Convert pan offset from stored (canonical/image pixel) space to display space.
func overheadOffsetToDisplay(
    storedX: Double, storedY: Double,
    imagePixelSize: CGSize,
    displayImageSize: CGSize
) -> CGSize {
    guard imagePixelSize.width > 0, imagePixelSize.height > 0,
          displayImageSize.width > 0, displayImageSize.height > 0 else {
        return .zero
    }
    return CGSize(
        width: CGFloat(storedX) * displayImageSize.width / imagePixelSize.width,
        height: CGFloat(storedY) * displayImageSize.height / imagePixelSize.height
    )
}

/// Convert pan offset from display space to stored (canonical/image pixel) space.
func overheadOffsetToStored(
    displayOffset: CGSize,
    imagePixelSize: CGSize,
    displayImageSize: CGSize
) -> (x: Double, y: Double) {
    guard imagePixelSize.width > 0, imagePixelSize.height > 0,
          displayImageSize.width > 0, displayImageSize.height > 0 else {
        return (0, 0)
    }
    return (
        Double(displayOffset.width * imagePixelSize.width / displayImageSize.width),
        Double(displayOffset.height * imagePixelSize.height / displayImageSize.height)
    )
}

/// Aspect ratio for overhead image container (width/height). 1.0 = square, matches report.
let overheadImageContainerAspectRatio: CGFloat = 1.0

/// Canonical container size for overhead transform. Edit Job uses 350×350; Locations tab and LocationMarkerView
/// use this size for transform calculations so zoom/pan appear consistent across all views.
let overheadCanonicalContainerSize: CGFloat = 350

private func overheadTransformFrameSize(imageSize: CGSize, scale: CGFloat, rotation: Double, minSize: CGSize) -> CGSize {
    let scaledW = imageSize.width * scale
    let scaledH = imageSize.height * scale
    let rotRad = CGFloat(rotation * .pi / 180)
    let boxW = scaledW * abs(cos(rotRad)) + scaledH * abs(sin(rotRad))
    let boxH = scaledW * abs(sin(rotRad)) + scaledH * abs(cos(rotRad))
    return CGSize(
        width: max(minSize.width, boxW),
        height: max(minSize.height, boxH)
    )
}

/// Scale factor to fit transformed content within container. Returns 1 if content already fits.
func overheadFitScale(imageSize: CGSize, scale: CGFloat, rotation: Double, containerSize: CGSize) -> CGFloat {
    let scaledW = imageSize.width * scale
    let scaledH = imageSize.height * scale
    let rotRad = CGFloat(rotation * .pi / 180)
    let boxW = scaledW * abs(cos(rotRad)) + scaledH * abs(sin(rotRad))
    let boxH = scaledW * abs(sin(rotRad)) + scaledH * abs(cos(rotRad))
    guard boxW > 0, boxH > 0, containerSize.width > 0, containerSize.height > 0 else { return 1 }
    return min(1, containerSize.width / boxW, containerSize.height / boxH)
}

/// Convert stored pixel position to geometry coordinates for dot display. Matches LocationMarkerView transform.
/// Use scaledLeft/scaledTop = 0 when image is at top-left (LocationMarkerView); use centered values when image is centered (OverheadImageContentView).
func overheadDotPositionToGeometry(
    location: CGPoint,
    imgSize: CGSize,
    imageSize: CGSize,
    scale: CGFloat,
    offset: CGSize,
    rotation: Double,
    frameSize: CGSize,
    fitScale: CGFloat,
    containerSize: CGSize,
    scaleToFill: CGFloat,
    contentOrigin: CGPoint,
    scaledLeft: CGFloat? = nil,
    scaledTop: CGFloat? = nil
) -> (CGFloat, CGFloat) {
    guard imgSize.width > 0, imgSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
        return (0, 0)
    }
    let dotPositionInImage = CGPoint(
        x: location.x * imageSize.width / imgSize.width,
        y: location.y * imageSize.height / imgSize.height
    )
    let scaledImageW = imageSize.width * scale
    let scaledImageH = imageSize.height * scale
    let left = scaledLeft ?? 0
    let top = scaledTop ?? 0
    let xBeforeOffset = left + dotPositionInImage.x * scale
    let yBeforeOffset = top + dotPositionInImage.y * scale
    let xInFrame = xBeforeOffset + offset.width
    let yInFrame = yBeforeOffset + offset.height
    let frameCenterX = frameSize.width / 2
    let frameCenterY = frameSize.height / 2
    let relX = xInFrame - frameCenterX
    let relY = yInFrame - frameCenterY
    let rotRad = rotation * .pi / 180
    let rotatedX = frameCenterX + relX * cos(rotRad) - relY * sin(rotRad)
    let rotatedY = frameCenterY + relX * sin(rotRad) + relY * cos(rotRad)
    let centerX = containerSize.width / 2
    let centerY = containerSize.height / 2
    let scaledFrameW = frameSize.width * fitScale
    let scaledFrameH = frameSize.height * fitScale
    let contentLeft = centerX - scaledFrameW / 2
    let contentTop = centerY - scaledFrameH / 2
    let containerX = contentLeft + rotatedX * fitScale
    let containerY = contentTop + rotatedY * fitScale
    let geometryX = contentOrigin.x + containerX * scaleToFill
    let geometryY = contentOrigin.y + containerY * scaleToFill
    return (geometryX, geometryY)
}

private func formatAddress(job: Job) -> String {
    var components: [String] = []
    let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
    if !addressToUse.isEmpty {
        components.append(addressToUse)
    }
    if let city = job.city, !city.isEmpty {
        components.append(city)
    }
    var cityStateZip: [String] = []
    if let state = job.state, !state.isEmpty {
        cityStateZip.append(state)
    }
    if let zip = job.zip, !zip.isEmpty {
        cityStateZip.append(zip)
    }
    if !cityStateZip.isEmpty {
        components.append(cityStateZip.joined(separator: " "))
    }
    return components.isEmpty ? "No address" : components.joined(separator: ", ")
}

/// Forces NSScrollView to use legacy scroller style (always-visible scrollbars) on macOS.
private struct LegacyScrollbarsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(_LegacyScrollbarsInjectionView())
    }
}

private struct _LegacyScrollbarsInjectionView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        _ScrollbarConfigView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class _ScrollbarConfigView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.configureScrollViews()
        }
    }
    private func configureScrollViews() {
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        func findAndConfigure(_ view: NSView) {
            if let sv = view as? NSScrollView {
                sv.scrollerStyle = .legacy
                sv.autohidesScrollers = false
            }
            for sub in view.subviews {
                findAndConfigure(sub)
            }
        }
        findAndConfigure(contentView)
    }
}

struct JobDetailView: View {
    let job: Job
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab = 0
    @State private var showingEditJob = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let jobId = job.jobId, jobId.count >= 13 {
                            Text(String(jobId.suffix(13)))
                                .font(.title)
                                .fontWeight(.bold)
                        } else {
                            Text(job.jobId ?? "Unknown Job")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        Text(job.clientName ?? "Unknown Client")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: job.status ?? "Unknown")
                }
                
                Button(action: {
                    showingEditJob = true
                }) {
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(.secondary)
                        Text(formatAddress(job: job))
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if let notes = job.notes, !notes.isEmpty {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Windows").tag(1)
                Text("Locations").tag(2)
                Text("Report").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            Divider()
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    JobOverviewView(job: job)
                case 1:
                    WindowsListView(job: job)
                case 2:
                    OverheadCanvasView(job: job)
                case 3:
                    ExportView(job: job)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            .clipped()
        }
        .navigationTitle("Job Details")
        .sheet(isPresented: $showingEditJob) {
            EditJobView(job: job)
                .frame(width: (NSScreen.main?.visibleFrame.width ?? 1440) * 0.75, height: 720)
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobDataUpdated)) { _ in
            // Refresh view when job data is updated
        }
    }
}

enum JobImageType: Identifiable {
    case overhead
    case frontOfHome
    case gauge
    var id: Self { self }
}

struct JobOverviewView: View {
    let job: Job
    @Environment(\.managedObjectContext) private var viewContext
    @State private var replaceOptionsImageType: JobImageType?
    @State private var showingFilePickerForOverhead = false
    @State private var showingFilePickerForFrontOfHome = false
    @State private var showingFilePickerForGauge = false
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Job Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Job ID", value: job.jobId ?? "N/A")
                        InfoRow(label: "Client", value: job.clientName ?? "N/A")
                        InfoRow(label: "Address", value: formatAddress(job: job))
                        InfoRow(label: "Status", value: job.status ?? "N/A")
                    }
                }
                
                GroupBox("Inspector Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Inspector", value: job.inspectorName ?? "N/A")
                        if let date = job.inspectionDate {
                            InfoRow(label: "Inspection Date", value: dateFormatter.string(from: date))
                        }
                    }
                }
                
                GroupBox("Test Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Test Procedure", value: job.testProcedure ?? "N/A")
                        InfoRow(label: "Water Pressure", value: "\(job.waterPressure) PSI")
                    }
                }
                
                GroupBox("Job Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            JobStatusBadge(status: job.currentStatus)
                            Spacer()
                        }
                        
                        if let reportDeliveredAt = job.reportDeliveredAt {
                            InfoRow(label: "Report Delivered", value: DateFormatter.shortDate.string(from: reportDeliveredAt))
                        }
                        
                        if let backedUpAt = job.backedUpToArchiveAt {
                            InfoRow(label: "Archived", value: DateFormatter.shortDate.string(from: backedUpAt))
                        }
                        
                        Divider()
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if job.reportDeliveredAt == nil {
                                    job.markReportDelivered()
                                } else {
                                    job.reportDeliveredAt = nil
                                    job.updateStatus()
                                }
                                do {
                                    try viewContext.save()
                                    NotificationCenter.default.post(name: .jobDataUpdated, object: job)
                                    refreshTrigger = UUID()
                                } catch {
                                    print("MYDEBUG → Failed to update report delivered status: \(error.localizedDescription)")
                                }
                            }) {
                                HStack(spacing: 12) {
                                    if job.reportDeliveredAt != nil {
                                        Image(systemName: "checkmark.square.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20))
                                    } else {
                                        Image(systemName: "square")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 20))
                                    }
                                    Image(systemName: "paperplane.fill")
                                    Text("Report Delivered")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                if job.backedUpToArchiveAt == nil {
                                    job.markBackedUpToArchive()
                                } else {
                                    job.backedUpToArchiveAt = nil
                                    job.updateStatus()
                                }
                                do {
                                    try viewContext.save()
                                    NotificationCenter.default.post(name: .jobDataUpdated, object: job)
                                    refreshTrigger = UUID()
                                } catch {
                                    print("MYDEBUG → Failed to update backed up status: \(error.localizedDescription)")
                                }
                            }) {
                                HStack(spacing: 12) {
                                    if job.backedUpToArchiveAt != nil {
                                        Image(systemName: "checkmark.square.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20))
                                    } else {
                                        Image(systemName: "square")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 20))
                                    }
                                    Image(systemName: "archivebox.fill")
                                    Text("Archived")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .id(refreshTrigger)
                }
                
                // Overhead Image (Overview Photo)
                if let imagePath = job.overheadImagePath {
                    GroupBox("Overhead Image / Overview Photo") {
                        if let image = loadOverheadImage(from: imagePath) {
                            OverheadImagePreviewView(image: image, job: job, size: 300)
                                .overlay(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            replaceOptionsImageType = .overhead
                                        }
                                )
                                .cornerRadius(8)
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                Text("Image not found")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 100)
                        }
                    }
                }
                
                // Front of Home Image
                if let imagePath = job.frontOfHomeImagePath {
                    GroupBox("Front of Home / Address Image") {
                        if let image = loadFrontOfHomeImage(from: imagePath) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .cornerRadius(8)
                                .overlay(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            replaceOptionsImageType = .frontOfHome
                                        }
                                )
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                Text("Image not found")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 100)
                        }
                    }
                }
                
                // Calibration Equipment Photo
                if let imagePath = job.gaugeImagePath {
                    GroupBox("Calibration Equipment Photo") {
                        if let image = loadGaugeImage(from: imagePath) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .cornerRadius(8)
                                .overlay(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            replaceOptionsImageType = .gauge
                                        }
                                )
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                                Text("Image not found")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 100)
                        }
                    }
                }
                
                if let windows = job.windows?.allObjects as? [Window] {
                    GroupBox("Windows") {
                        Text("\(windows.count) windows")
                            .font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
        .modifier(LegacyScrollbarsModifier())
        .sheet(item: $replaceOptionsImageType) { imageType in
            ReplaceImageOptionsSheet(
                selectedPhotosItem: $selectedPhotosItem,
                onFileSelected: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        switch imageType {
                        case .overhead: showingFilePickerForOverhead = true
                        case .frontOfHome: showingFilePickerForFrontOfHome = true
                        case .gauge: showingFilePickerForGauge = true
                        }
                    }
                },
                onCancel: { }
            )
        }
        .fileImporter(
            isPresented: $showingFilePickerForOverhead,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .bmp, .gif],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result, for: .overhead)
        }
        .fileImporter(
            isPresented: $showingFilePickerForFrontOfHome,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .bmp, .gif],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result, for: .frontOfHome)
        }
        .fileImporter(
            isPresented: $showingFilePickerForGauge,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .bmp, .gif],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result, for: .gauge)
        }
        .onChange(of: selectedPhotosItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        if let imageType = replaceOptionsImageType {
                            saveImage(nsImage, for: imageType)
                            replaceOptionsImageType = nil
                        }
                        selectedPhotosItem = nil
                    }
                }
            }
        }
    }
    
    private func handleFilePickerResult(_ result: Result<[URL], Error>, for imageType: JobImageType) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let image = NSImage(contentsOf: url) {
                saveImage(image, for: imageType)
            }
        case .failure(let error):
            print("MYDEBUG →", "File picker error: \(error.localizedDescription)")
        }
    }
    
    private func saveImage(_ image: NSImage, for imageType: JobImageType) {
        switch imageType {
        case .overhead:
            saveOverheadImage(image, for: job)
        case .frontOfHome:
            saveFrontOfHomeImage(image, for: job)
        case .gauge:
            saveGaugeImage(image, for: job)
        }
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Failed to save: \(error.localizedDescription)")
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
            print("MYDEBUG →", "Failed to save overhead image: \(error.localizedDescription)")
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
            print("MYDEBUG →", "Failed to save front of home image: \(error.localizedDescription)")
        }
    }
    
    private func saveGaugeImage(_ image: NSImage, for job: Job) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("gauge_images")
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let fileName = "\(job.jobId ?? UUID().uuidString)_gauge.jpg"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            try imageData.write(to: fileURL)
            job.gaugeImagePath = fileName
        } catch {
            print("MYDEBUG →", "Failed to save gauge image: \(error.localizedDescription)")
        }
    }
    
    private func loadFrontOfHomeImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("front_of_home_images").appendingPathComponent(imagePath)
        
        print("🔍 Loading front of home image:")
        print("   Image path: \(imagePath)")
        print("   Full URL: \(imageURL.path)")
        print("   File exists: \(FileManager.default.fileExists(atPath: imageURL.path))")
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("⚠️ Front of home image not found at: \(imageURL.path)")
            // List files in directory for debugging
            let imagesDir = documentsDirectory.appendingPathComponent("front_of_home_images")
            if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) {
                print("   Files in front_of_home_images directory: \(files)")
            }
            return nil
        }
        
        return NSImage(contentsOf: imageURL)
    }
    
    private func loadGaugeImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("gauge_images").appendingPathComponent(imagePath)
        
        print("🔍 Loading gauge image:")
        print("   Image path: \(imagePath)")
        print("   Full URL: \(imageURL.path)")
        print("   File exists: \(FileManager.default.fileExists(atPath: imageURL.path))")
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("⚠️ Gauge image not found at: \(imageURL.path)")
            // List files in directory for debugging
            let imagesDir = documentsDirectory.appendingPathComponent("gauge_images")
            if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) {
                print("   Files in gauge_images directory: \(files)")
            }
            return nil
        }
        
        return NSImage(contentsOf: imageURL)
    }
    
    private func loadOverheadImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
        
        print("🔍 Loading overhead image:")
        print("   Image path: \(imagePath)")
        print("   Full URL: \(imageURL.path)")
        print("   File exists: \(FileManager.default.fileExists(atPath: imageURL.path))")
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            print("⚠️ Overhead image not found at: \(imageURL.path)")
            // List files in directory for debugging
            let imagesDir = documentsDirectory.appendingPathComponent("overhead_images")
            if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) {
                print("   Files in overhead_images directory: \(files)")
            }
            return nil
        }
        
        return NSImage(contentsOf: imageURL)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct WindowsListView: View {
    let job: Job
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let windows = job.windows?.allObjects as? [Window], !windows.isEmpty {
                    ForEach(windows.sorted(by: { ($0.windowNumber ?? "") < ($1.windowNumber ?? "") }), id: \.objectID) { window in
                        WindowRowView(window: window)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Windows")
                            .font(.title2)
                        Text("Add windows to this job")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
        .modifier(LegacyScrollbarsModifier())
    }
}

struct WindowRowView: View {
    @ObservedObject var window: Window
    @State private var showingWindowEditor = false
    
    var body: some View {
        Button(action: {
            showingWindowEditor = true
        }) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Window \(window.windowNumber ?? "?")")
                            .font(.headline)
                        Spacer()
                        if window.isInaccessible {
                            StatusBadge(status: "Not Tested")
                        } else if let testResult = window.testResult {
                            StatusBadge(status: testResult)
                        } else {
                            StatusBadge(status: "Pending")
                        }
                    }
                    if let windowType = window.windowType {
                        Text("Type: \(windowType)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if window.width > 0 && window.height > 0 {
                        Text("Size: \(String(format: "%.1f", window.width))\" × \(String(format: "%.1f", window.height))\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let material = window.material {
                        Text("Material: \(material)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let notes = window.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    if let photos = window.photos?.allObjects as? [Photo], !photos.isEmpty {
                        HStack {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                            Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingWindowEditor) {
            WindowEditorView(window: window)
                .frame(width: 1000, height: 800)
        }
    }
}

/// Read-only overhead image with transform, for overview display.
private struct OverheadImagePreviewView: View {
    let image: NSImage
    let job: Job
    let size: CGFloat
    @State private var imageSize: CGSize = .zero
    
    private var scale: CGFloat {
        max(1.0, CGFloat(1.0))
    }
    private var offset: CGSize {
        let imgSize = overheadImagePixelSize(image)
        return overheadOffsetToDisplay(
            storedX: 0, storedY: 0,
            imagePixelSize: imgSize,
            displayImageSize: imageSize
        )
    }
    private var rotation: Double { 0 }
    
    var body: some View {
        let containerSize = CGSize(width: size, height: size)
        let fs = overheadTransformFrameSize(imageSize: imageSize, scale: scale, rotation: rotation, minSize: containerSize)
        let fitScale = overheadFitScale(imageSize: imageSize, scale: scale, rotation: rotation, containerSize: containerSize)
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(
                    GeometryReader { imageGeometry in
                        Color.clear
                            .onAppear {
                                let frameSize = imageGeometry.size
                                let imgSize = CGSize(width: image.size.width, height: image.size.height)
                                let imageAspectRatio = imgSize.width / imgSize.height
                                if imageAspectRatio > (frameSize.width / frameSize.height) {
                                    imageSize = CGSize(width: frameSize.width, height: frameSize.width / imageAspectRatio)
                                } else {
                                    imageSize = CGSize(width: frameSize.height * imageAspectRatio, height: frameSize.height)
                                }
                            }
                    }
                )
        }
        .scaleEffect(scale)
        .offset(offset)
        .rotationEffect(.degrees(rotation))
        .frame(width: fs.width, height: fs.height)
        .scaleEffect(fitScale)
        .frame(width: size, height: size)
        .clipped()
    }
}

private struct OverheadImageContentView: View {
    let image: NSImage
    let geometry: GeometryProxy
    let job: Job
    let windows: [Window]
    @Binding var showingReplaceOptions: Bool
    var minSizeOverride: CGSize? = nil
    
    private var effectiveMinSize: CGSize {
        minSizeOverride ?? geometry.size
    }
    /// Use canonical size for transform so zoom/pan matches Edit Job and LocationMarkerView.
    private var transformContainerSize: CGSize {
        CGSize(width: overheadCanonicalContainerSize, height: overheadCanonicalContainerSize)
    }
    private var scale: CGFloat {
        max(1.0, CGFloat(1.0))
    }
    private var offset: CGSize {
        let imgSize = overheadImagePixelSize(image)
        return overheadOffsetToDisplay(
            storedX: 0, storedY: 0,
            imagePixelSize: imgSize,
            displayImageSize: imageFittedToFrameSize
        )
    }
    private var rotation: Double { 0 }
    private var frameSize: CGSize {
        overheadTransformFrameSize(
            imageSize: displayImageSize,
            scale: scale,
            rotation: rotation,
            minSize: transformContainerSize
        )
    }
    
    var body: some View {
        let fs = frameSize
        let fitScale = overheadFitScale(imageSize: displayImageSize, scale: scale, rotation: rotation, containerSize: transformContainerSize)
        let scaleToFill = min(effectiveMinSize.width, effectiveMinSize.height) / overheadCanonicalContainerSize
        let contentSide = overheadCanonicalContainerSize * scaleToFill
        let contentOrigin = CGPoint(
            x: (effectiveMinSize.width - contentSide) / 2,
            y: (effectiveMinSize.height - contentSide) / 2
        )
        return ZStack(alignment: .topLeading) {
            imageOnly
                .scaleEffect(scale)
                .offset(offset)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: fs.width, height: fs.height)
        .scaleEffect(fitScale)
        .frame(width: overheadCanonicalContainerSize, height: overheadCanonicalContainerSize)
        .scaleEffect(scaleToFill)
        .frame(width: effectiveMinSize.width, height: effectiveMinSize.height)
        .contentShape(Rectangle())
        .clipped()
        .overlay {
            dotsOverlay(
                contentOrigin: contentOrigin,
                scaleToFill: scaleToFill,
                fitScale: fitScale
            )
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { showingReplaceOptions = true }) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
    
    /// Display size of the image when fitted to transform container (canonical). Matches Edit Job for consistent zoom.
    private var displayImageSize: CGSize {
        let pixelSize = overheadImagePixelSize(image)
        let imageAspectRatio = pixelSize.width / max(1, pixelSize.height)
        let containerAspectRatio = transformContainerSize.width / max(1, transformContainerSize.height)
        if imageAspectRatio > containerAspectRatio {
            return CGSize(width: transformContainerSize.width, height: transformContainerSize.width / imageAspectRatio)
        } else {
            return CGSize(width: transformContainerSize.height * imageAspectRatio, height: transformContainerSize.height)
        }
    }
    
    /// Image size when fitted to frameSize. Used for dot positioning to avoid GeometryReader layout timing issues.
    private var imageFittedToFrameSize: CGSize {
        let pixelSize = overheadImagePixelSize(image)
        let imageAspectRatio = pixelSize.width / max(1, pixelSize.height)
        let fs = frameSize
        let containerAspectRatio = fs.width / max(1, fs.height)
        if imageAspectRatio > containerAspectRatio {
            return CGSize(width: fs.width, height: fs.width / imageAspectRatio)
        } else {
            return CGSize(width: fs.height * imageAspectRatio, height: fs.height)
        }
    }
    
    private var imageOnly: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
    
    /// Dots positioned in geometry coordinates using same transform as LocationMarkerView.
    /// Uses scaledLeft=0, scaledTop=0 to match LocationMarkerView's top-leading image layout.
    @ViewBuilder
    private func dotsOverlay(contentOrigin: CGPoint, scaleToFill: CGFloat, fitScale: CGFloat) -> some View {
        let windowsWithPositions = windows.filter { $0.xPosition > 0 && $0.yPosition > 0 }
        let imgSize = overheadImagePixelSize(image)
        let fittedSize = imageFittedToFrameSize
        let fs = frameSize
        let containerSize = transformContainerSize
        if imgSize.width > 0, imgSize.height > 0, fittedSize.width > 0, fittedSize.height > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(windowsWithPositions, id: \.objectID) { window in
                    let location = CGPoint(x: window.xPosition, y: window.yPosition)
                    let (geometryX, geometryY) = overheadDotPositionToGeometry(
                        location: location,
                        imgSize: imgSize,
                        imageSize: fittedSize,
                        scale: scale,
                        offset: offset,
                        rotation: rotation,
                        frameSize: fs,
                        fitScale: fitScale,
                        containerSize: containerSize,
                        scaleToFill: scaleToFill,
                        contentOrigin: contentOrigin
                    )
                    OverheadCanvasWindowDotView(window: window)
                        .position(x: geometryX, y: geometryY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: effectiveMinSize.width, height: effectiveMinSize.height)
        }
    }
}

struct OverheadCanvasView: View {
    let job: Job
    @Environment(\.managedObjectContext) private var viewContext
    @State private var image: NSImage?
    @State private var showingReplaceOptions = false
    @State private var showingFilePicker = false
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var locationsRefreshID = UUID()
    
    private var windows: [Window] {
        guard let windowsSet = job.windows else { return [] }
        return (windowsSet.allObjects as? [Window] ?? []).sorted { ($0.windowNumber ?? "") < ($1.windowNumber ?? "") }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let squareMinSize = CGSize(width: side, height: side)
            ZStack {
                Color(NSColor.controlBackgroundColor)
                    .ignoresSafeArea()
                
                if let image = image {
                    OverheadImageContentView(
                        image: image,
                        geometry: geometry,
                        job: job,
                        windows: windows,
                        showingReplaceOptions: $showingReplaceOptions,
                        minSizeOverride: squareMinSize
                    )
                    .id(locationsRefreshID)
                    .frame(width: side, height: side)
                } else if let imagePath = job.overheadImagePath {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading overhead image...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        loadImage()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Overhead Image")
                            .font(.title2)
                        Text("Add an overhead image to this job")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding()
        .onAppear {
            loadImage()
            // Refresh job and windows when Locations tab appears so placed dots show
            // (user may have placed dots while on Windows tab, so onReceive never ran)
            viewContext.refresh(job, mergeChanges: true)
            for w in windows {
                viewContext.refresh(w, mergeChanges: true)
            }
            let withPositions = windows.filter { $0.xPosition > 0 && $0.yPosition > 0 }
            print("MYDEBUG → OverheadCanvasView.onAppear: windows=\(windows.count), withPositions=\(withPositions.count), positions=\(withPositions.map { "\($0.windowNumber ?? "?"):(\($0.xPosition),\($0.yPosition))" })")
            locationsRefreshID = UUID()
        }
        .onChange(of: job.overheadImagePath) { _, _ in
            loadImage()
        }
        .sheet(isPresented: $showingReplaceOptions) {
            ReplaceImageOptionsSheet(
                selectedPhotosItem: $selectedPhotosItem,
                onFileSelected: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingFilePicker = true
                    }
                },
                onCancel: { }
            )
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .bmp, .gif],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let newImage = NSImage(contentsOf: url) {
                    saveOverheadImage(newImage, for: job)
                }
            case .failure(let error):
                print("MYDEBUG →", "File picker error: \(error.localizedDescription)")
            }
        }
        .onChange(of: selectedPhotosItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        saveOverheadImage(nsImage, for: job)
                        selectedPhotosItem = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobDataUpdated)) { notification in
            if let postedJob = notification.object as? Job, postedJob.objectID == job.objectID {
                viewContext.refresh(job, mergeChanges: true)
                for w in windows {
                    viewContext.refresh(w, mergeChanges: true)
                }
                locationsRefreshID = UUID()
            }
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
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Failed to save overhead image: \(error.localizedDescription)")
        }
    }
    
    private func loadImage() {
        guard let imagePath = job.overheadImagePath else {
            print("⚠️ No overhead image path for job: \(job.jobId ?? "unknown")")
            print("   Job overheadImagePath property: \(job.overheadImagePath ?? "nil")")
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
        
        print("🔍 Loading overhead image:")
        print("   Image path from job: \(imagePath)")
        print("   Full URL: \(imageURL.path)")
        print("   File exists: \(FileManager.default.fileExists(atPath: imageURL.path))")
        
        // List files in overhead_images directory for debugging
        let overheadDir = documentsDirectory.appendingPathComponent("overhead_images")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: overheadDir.path) {
            print("   Files in overhead_images directory: \(files)")
        }
        
        if FileManager.default.fileExists(atPath: imageURL.path) {
            if let loadedImage = NSImage(contentsOf: imageURL) {
                self.image = loadedImage
                print("✅ Successfully loaded overhead image")
            } else {
                print("❌ Failed to create NSImage from file")
            }
        } else {
            print("❌ Image file does not exist at path")
        }
    }
}

/// Dot view for OverheadCanvasView - parent positions via .position()
struct OverheadCanvasWindowDotView: View {
    let window: Window
    
    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .frame(width: 44, height: 44)
            
            if let windowNumber = window.windowNumber {
                Text(OverheadCanvasWindowDotView.extractNumberFromSpecimenName(windowNumber))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(window.isInaccessible ? .black : .white)
            }
        }
    }
    
    private var dotColor: Color {
        if window.isInaccessible {
            return .gray
        } else if window.testResult == "Pass" {
            return .green
        } else if window.testResult == "Fail" {
            return .red
        } else {
            return .blue
        }
    }
    
    private static func extractNumberFromSpecimenName(_ name: String) -> String {
        if let numberRange = name.range(of: #"\d+"#, options: .regularExpression) {
            return String(name[numberRange])
        }
        return name
    }
}

struct WindowDotView: View {
    let window: Window
    let imageSize: CGSize
    let originalImageSize: NSSize
    let viewSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            let position = convertImageToViewPosition(
                x: window.xPosition,
                y: window.yPosition,
                imageSize: imageSize,
                viewSize: geometry.size,
                originalImageSize: CGSize(width: originalImageSize.width, height: originalImageSize.height)
            )
            
            ZStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .frame(width: 44, height: 44)
                    .position(x: position.x, y: position.y)
                
                if let windowNumber = window.windowNumber {
                    Text(extractNumberFromSpecimenName(windowNumber))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(window.isInaccessible ? .black : .white)
                        .position(x: position.x, y: position.y)
                }
            }
        }
    }
    
    private var dotColor: Color {
        if window.isInaccessible {
            return .gray
        } else if window.testResult == "Pass" {
            return .green
        } else if window.testResult == "Fail" {
            return .red
        } else {
            return .blue
        }
    }
    
    private func convertImageToViewPosition(x: Double, y: Double, imageSize: CGSize, viewSize: CGSize, originalImageSize: CGSize) -> CGPoint {
        let imageAspectRatio = originalImageSize.width / originalImageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider - letterboxed
            let imageWidth = viewSize.width
            let imageHeight = viewSize.width / imageAspectRatio
            let yOffset = (viewSize.height - imageHeight) / 2
            
            return CGPoint(
                x: CGFloat(x) * imageWidth / originalImageSize.width,
                y: CGFloat(y) * imageHeight / originalImageSize.height + yOffset
            )
        } else {
            // Image is taller - pillarboxed
            let imageHeight = viewSize.height
            let imageWidth = viewSize.height * imageAspectRatio
            let xOffset = (viewSize.width - imageWidth) / 2
            
            return CGPoint(
                x: CGFloat(x) * imageWidth / originalImageSize.width + xOffset,
                y: CGFloat(y) * imageHeight / originalImageSize.height
            )
        }
    }
    
    private func extractNumberFromSpecimenName(_ name: String) -> String {
        // Extract just the number from names like "Specimen 2", "Window 3", etc.
        if let numberRange = name.range(of: #"\d+"#, options: .regularExpression) {
            return String(name[numberRange])
        }
        return name
    }
}

enum RecipientType: String, CaseIterable {
    case mrLevy = "Mr. Levy"
    case dynamicClient = "Dynamic Client Name"
}

enum ReportSelectionMode: String, CaseIterable {
    case generateNew = "Generate Report"
    case selectExisting = "Select Existing Report"
}

struct ExportView: View {
    let job: Job
    @State private var isExportingDocx = false
    @State private var docxError: String?
    @State private var docxFileURL: URL?
    @State private var isExportingPdf = false
    @State private var pdfError: String?
    @State private var pdfFileURL: URL?
    @State private var isExportingFullPackage = false
    @State private var fullPackageFileURL: URL?
    @State private var fullPackageError: String?
    
    @State private var showingCustomizationSheet = false
    @State private var includeEngineeringLetter = false
    
    // Email draft state
    @State private var recipientType: RecipientType = .mrLevy
    @State private var recipientEmail: String = "rclarke009@gmail.com"
    @State private var isCreatingEmailDraft = false
    @State private var emailDraftError: String?
    @State private var reportSelectionMode: ReportSelectionMode = .generateNew
    @State private var selectedReportURL: URL?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GroupBox("Export Report") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Generate and export reports for this job")
                            .foregroundColor(.secondary)
                        
                        // DOCX Export
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text("Word Document (DOCX)")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Export a formatted Word document report")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                exportDocxReport()
                            }) {
                                HStack {
                                    if isExportingDocx {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                    Text(isExportingDocx ? "Exporting..." : "Export DOCX")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExportingDocx)
                            
                            if let error = docxError {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if let fileURL = docxFileURL {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Exported: \(fileURL.lastPathComponent)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // PDF Export
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                Text("PDF Document")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Export a formatted PDF report")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                exportPdfReport()
                            }) {
                                HStack {
                                    if isExportingPdf {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                    Text(isExportingPdf ? "Exporting..." : "Export PDF")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExportingPdf)
                            
                            if let error = pdfError {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if let fileURL = pdfFileURL {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Exported: \(fileURL.lastPathComponent)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // Full Job Package Export
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                Text("Full Job Package")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Export complete job data for transfer to another device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                exportFullJobPackage()
                            }) {
                                HStack {
                                    if isExportingFullPackage {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                    Text(isExportingFullPackage ? "Exporting..." : "Export Full Package")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExportingFullPackage)
                            
                            if let error = fullPackageError {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            if let fileURL = fullPackageFileURL {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Exported: \(fileURL.lastPathComponent)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // Customize Report
                        Button(action: {
                            showingCustomizationSheet = true
                        }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Customize Report")
                                Spacer()
                                if hasCustomHurricaneImage() || hasCustomWeatherText() || hasConclusionComment() || includeEngineeringLetter {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.bordered)
                        
                        // Email Draft
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "envelope")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                Text("Email Draft")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text("Create an email draft with the report attached")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Recipient type picker
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Recipient:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Picker("Recipient Type", selection: $recipientType) {
                                        ForEach(RecipientType.allCases, id: \.self) { type in
                                            Text(type.rawValue).tag(type)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: recipientType) { _, newValue in
                                        updateEmailAddress(for: newValue)
                                    }
                                }
                                
                                // Email address field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Email Address:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    TextField("Email address", text: $recipientEmail)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                // Report selection mode
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Report:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Picker("Report Selection Mode", selection: $reportSelectionMode) {
                                        ForEach(ReportSelectionMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: reportSelectionMode) { _, newValue in
                                        if newValue == .generateNew {
                                            selectedReportURL = nil
                                        }
                                    }
                                    
                                    if reportSelectionMode == .selectExisting {
                                        HStack {
                                            if let selectedURL = selectedReportURL {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(selectedURL.lastPathComponent)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                    Button("Change File...") {
                                                        selectReportFile()
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .font(.caption)
                                                }
                                            } else {
                                                Button("Select Report File...") {
                                                    selectReportFile()
                                                }
                                                .buttonStyle(.bordered)
                                                .font(.caption)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                
                                // Note about from address
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Note: Please select 'contact@true-reports.com' as the sender in Mail.app")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            Button(action: {
                                createEmailDraft()
                            }) {
                                HStack {
                                    if isCreatingEmailDraft {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "envelope.badge")
                                    }
                                    Text(isCreatingEmailDraft ? "Creating..." : "Create Email Draft")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCreatingEmailDraft)
                            
                            if let error = emailDraftError {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
        .modifier(LegacyScrollbarsModifier())
        .onAppear {
            updateEmailAddress(for: recipientType)
            includeEngineeringLetter = job.includeEngineeringLetter ?? false
        }
        .sheet(isPresented: $showingCustomizationSheet) {
            ReportCustomizationSheetView(
                job: job,
                includeEngineeringLetter: $includeEngineeringLetter,
                onSave: {
                    showingCustomizationSheet = false
                },
                onCancel: {
                    showingCustomizationSheet = false
                }
            )
            .frame(width: (NSScreen.main?.visibleFrame.width ?? 1440) * 0.75, height: 720)
        }
    }
    
    private func hasCustomHurricaneImage() -> Bool {
        guard let imagePath = job.customHurricaneImagePath else { return false }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("custom_hurricane_images").appendingPathComponent(imagePath)
        return FileManager.default.fileExists(atPath: imageURL.path)
    }
    
    private func hasCustomWeatherText() -> Bool {
        guard let text = job.customWeatherText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func hasConclusionComment() -> Bool {
        guard let comment = job.conclusionComment else { return false }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func exportDocxReport() {
        guard !isExportingDocx else { return }
        isExportingDocx = true
        docxError = nil
        
        Task {
            do {
                let package = FieldResultsPackage(job: job, exportDirectory: URL(fileURLWithPath: ""))
                let docURL = try await package.generateStandaloneDOCXReport()
                await MainActor.run {
                    docxFileURL = docURL
                    isExportingDocx = false
                    // Open the file location
                    NSWorkspace.shared.activateFileViewerSelecting([docURL])
                }
            } catch {
                print("❌ DOCX export failed: \(error.localizedDescription)")
                await MainActor.run {
                    docxError = error.localizedDescription
                    isExportingDocx = false
                }
            }
        }
    }
    
    private func exportPdfReport() {
        guard !isExportingPdf else { return }
        isExportingPdf = true
        pdfError = nil

        // Refresh job from store so we have latest persisted value; use job as source of truth, fall back to @State
        job.managedObjectContext?.refresh(job, mergeChanges: true)
        let includeEngLetter = job.includeEngineeringLetter ?? includeEngineeringLetter

        Task {
            do {
                let package = FieldResultsPackage(job: job, exportDirectory: URL(fileURLWithPath: ""))
                let pdfURL = try await package.exportPDFReport(includeEngineeringLetter: includeEngLetter)
                await MainActor.run {
                    pdfFileURL = pdfURL
                    isExportingPdf = false
                }
            } catch {
                print("❌ PDF export failed: \(error.localizedDescription)")
                await MainActor.run {
                    pdfError = error.localizedDescription
                    isExportingPdf = false
                }
            }
        }
    }
    
    private func exportFullJobPackage() {
        guard !isExportingFullPackage else { return }
        isExportingFullPackage = true
        fullPackageError = nil
        fullPackageFileURL = nil
        
        Task {
            do {
                job.managedObjectContext?.refresh(job, mergeChanges: true)
                let includeEngLetter = job.includeEngineeringLetter ?? includeEngineeringLetter
                let exporter = FullJobPackageExporter(job: job, includeEngineeringLetterOverride: includeEngLetter)
                let zipURL = try await exporter.export()
                
                await MainActor.run {
                    fullPackageFileURL = zipURL
                    isExportingFullPackage = false
                    // Open the file location
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                }
            } catch {
                print("❌ Full Job Package export failed: \(error.localizedDescription)")
                await MainActor.run {
                    fullPackageError = error.localizedDescription
                    isExportingFullPackage = false
                }
            }
        }
    }
    
    // MARK: - Email Draft Functions
    
    private func updateEmailAddress(for recipientType: RecipientType) {
        switch recipientType {
        case .mrLevy:
            recipientEmail = "rclarke009@gmail.com"
        case .dynamicClient:
            // Try to extract email from notes, otherwise leave empty for user to enter
            if let email = extractEmailFromNotes() {
                recipientEmail = email
            } else {
                recipientEmail = ""
            }
        }
    }
    
    private func extractEmailFromNotes() -> String? {
        guard let notes = job.notes else { return nil }
        
        // Simple email regex pattern
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []),
           let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
           let range = Range(match.range, in: notes) {
            return String(notes[range])
        }
        
        return nil
    }
    
    private func createEmailDraft() {
        guard !isCreatingEmailDraft else { return }
        guard !recipientEmail.isEmpty else {
            emailDraftError = "Please enter an email address"
            return
        }
        
        if reportSelectionMode == .selectExisting {
            guard let selectedURL = selectedReportURL else {
                emailDraftError = "Please select a report file"
                return
            }
            guard FileManager.default.fileExists(atPath: selectedURL.path) else {
                emailDraftError = "Selected file does not exist"
                return
            }
        }
        
        isCreatingEmailDraft = true
        emailDraftError = nil
        
        Task {
            do {
                let pdfURL: URL
                
                if reportSelectionMode == .selectExisting, let selectedURL = selectedReportURL {
                    // Use selected file
                    pdfURL = selectedURL
                    print("MYDEBUG →", "Using selected report: \(pdfURL.path)")
                } else {
                    // Generate new PDF report
                    print("MYDEBUG →", "Generating PDF report for email draft...")
                    job.managedObjectContext?.refresh(job, mergeChanges: true)
                    let includeEngLetter = job.includeEngineeringLetter ?? includeEngineeringLetter
                    let package = FieldResultsPackage(job: job, exportDirectory: URL(fileURLWithPath: ""))
                    pdfURL = try await package.exportPDFReport(includeEngineeringLetter: includeEngLetter)
                    print("MYDEBUG →", "PDF generated at: \(pdfURL.path)")
                }
                
                // Create email draft
                await MainActor.run {
                    createEmailDraftWithPDF(pdfURL: pdfURL)
                    isCreatingEmailDraft = false
                }
            } catch {
                print("MYDEBUG →", "Error creating email draft: \(error.localizedDescription)")
                await MainActor.run {
                    emailDraftError = error.localizedDescription
                    isCreatingEmailDraft = false
                }
            }
        }
    }
    
    private func selectReportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "docx")!]
        panel.title = "Select Report File"
        panel.message = "Choose a PDF or DOCX report file to attach"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedReportURL = url
                print("MYDEBUG →", "Selected report file: \(url.path)")
            }
        }
    }
    
    private func createEmailDraftWithPDF(pdfURL: URL) {
        guard let emailService = NSSharingService(named: .composeEmail) else {
            emailDraftError = "Unable to create email service. Please ensure Mail.app is configured."
            return
        }
        
        // Determine recipient name
        let recipientName: String
        switch recipientType {
        case .mrLevy:
            recipientName = "Mr. Levy"
        case .dynamicClient:
            recipientName = job.clientName ?? "Client"
        }
        
        // Format address
        let address = formatAddress(job: job)
        
        // Get signature image URL for attachment
        let signatureImageURL = loadSignatureImageURL()
        
        // Create email body - try using NSAttributedString with HTML for better image support
        let emailBody: Any
        var usingBase64 = false
        var imageDataSize: Int = 0
        
        if let signatureURL = signatureImageURL {
            // Load image data and embed as base64 (more reliable than CID for Mail.app)
            // Resize image to reasonable size for email (max 300px width)
            if let nsImage = NSImage(contentsOf: signatureURL) {
                let originalSize = nsImage.size
                imageDataSize = (try? Data(contentsOf: signatureURL))?.count ?? 0
                
                // Resize image to max 150px width for email
                let maxWidth: CGFloat = 150
                let scale = originalSize.width > maxWidth ? maxWidth / originalSize.width : 1.0
                let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
                
                let resizedImage = NSImage(size: newSize)
                resizedImage.lockFocus()
                nsImage.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: originalSize), operation: .sourceOver, fraction: 1.0)
                resizedImage.unlockFocus()
                
                // Convert resized image to data
                let imageData: Data?
                let mimeType: String
                if signatureURL.pathExtension.lowercased() == "png" {
                    mimeType = "image/png"
                    if let tiffData = resizedImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData) {
                        imageData = bitmapRep.representation(using: .png, properties: [:])
                    } else {
                        imageData = nil
                    }
                } else {
                    mimeType = "image/jpeg"
                    if let tiffData = resizedImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData) {
                        imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                    } else {
                        imageData = nil
                    }
                }
                
                if let finalImageData = imageData {
                    let imageBase64 = finalImageData.base64EncodedString()
                    emailBody = formatEmailBodyWithBase64(recipientName: recipientName, address: address, imageBase64: imageBase64, mimeType: mimeType)
                    usingBase64 = true
                    print("MYDEBUG →", "Using base64 embedded image in email body (resized to \(Int(newSize.width))x\(Int(newSize.height)))")
                } else {
                    // Fallback to CID reference if resize fails
                    let signatureImageName = signatureURL.lastPathComponent
                    emailBody = formatEmailBody(recipientName: recipientName, address: address, signatureImageName: signatureImageName)
                    print("MYDEBUG →", "Failed to resize image, using CID reference")
                }
            } else {
                // Fallback to CID reference
                let signatureImageName = signatureURL.lastPathComponent
                emailBody = formatEmailBody(recipientName: recipientName, address: address, signatureImageName: signatureImageName)
                print("MYDEBUG →", "Using CID reference for signature image")
            }
        } else {
            emailBody = formatEmailBody(recipientName: recipientName, address: address, signatureImageName: nil)
        }
        
        // Set email properties
        emailService.recipients = [recipientEmail]
        emailService.subject = "Window Test Report - \(address)"
        
        // Prepare items: HTML body and PDF report
        // Note: If using base64, we don't need to attach the image separately
        var items: [Any] = [emailBody, pdfURL]
        
        // Only attach image separately if using CID reference (NOT base64)
        let willAttachImage = signatureImageURL != nil && !usingBase64
        
        if willAttachImage {
            items.append(signatureImageURL!)
        }
        
        // Perform the service with body and attachments
        emailService.perform(withItems: items)
        
        print("MYDEBUG →", "Email draft created for: \(recipientEmail)")
    }
    
    private func formatEmailBodyWithBase64(recipientName: String, address: String, imageBase64: String, mimeType: String) -> String {
        // Use more restrictive sizing and ensure only one image tag
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; line-height: 1.6; color: #333;">
            <p>Hello \(recipientName),</p>
            <p>Please find the attached Window Test Report for the claim at \(address).</p>
            <p><br><br></p>
            <p>Hope you have a great day,<br>Rebecca</p>
            <hr style="border: none; border-top: 1px solid #ccc; margin: 20px 0;">
            <p>Rebecca Clarke<br>Office Manager</p>
            <p>contact@true-reports.com<br>www.True-Reports.com</p>
            <p>— Inspections: Roofs, Windows, Structural, Flood —</p>
            <p><img src="data:\(mimeType);base64,\(imageBase64)" alt="True Reports Signature" width="150" style="max-width: 150px; width: 150px; height: auto; margin-top: 10px; display: block;"></p>
        </body>
        </html>
        """
    }
    
    private func formatEmailBody(recipientName: String, address: String, signatureImageName: String?) -> String {
        // Use CID reference for signature image
        // Mail.app typically uses the attachment filename as the Content-ID
        // Try multiple CID formats that Mail.app might recognize
        var signatureImageTag = ""
        if let imageName = signatureImageName {
            // Try using the filename without extension as CID
            let cidName = (imageName as NSString).deletingPathExtension
            signatureImageTag = """
            <p><img src="cid:\(cidName)" alt="True Reports Signature" style="max-width: 150px; height: auto; margin-top: 10px;"></p>
            """
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 14px; line-height: 1.6; color: #333;">
            <p>Hello \(recipientName),</p>
            <p>Please find the attached Window Test Report for the claim at \(address).</p>
            <p><br><br></p>
            <p>Hope you have a great day,<br>Rebecca</p>
            <hr style="border: none; border-top: 1px solid #ccc; margin: 20px 0;">
            <p>Rebecca Clarke<br>Office Manager</p>
            <p>contact@true-reports.com<br>www.True-Reports.com</p>
            <p>— Inspections: Roofs, Windows, Structural, Flood —</p>
            \(signatureImageTag)
        </body>
        </html>
        """
    }
    
    private func loadSignatureImageURL() -> URL? {
        // Detect current appearance
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua || 
                        NSApp.effectiveAppearance.name == .vibrantDark ||
                        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Get image path based on appearance
        let imageName = isDarkMode ? "TrueLogoDark.png" : "TrueLogoEmailLight.jpg"
        
        // Try to load from bundle/images directory
        let resourceName = imageName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "")
        let resourceType = imageName.hasSuffix(".png") ? "png" : "jpg"
        
        if let imagePath = Bundle.main.path(forResource: resourceName, ofType: resourceType, inDirectory: "images") {
            if FileManager.default.fileExists(atPath: imagePath) {
                print("MYDEBUG →", "Found signature image in bundle: \(imagePath)")
                return URL(fileURLWithPath: imagePath)
            }
        }
        
        // Priority 1: Try to load from documents directory (most reliable)
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("images").appendingPathComponent(imageName)
        
        if FileManager.default.fileExists(atPath: imageURL.path) {
            print("MYDEBUG →", "Found signature image in documents: \(imageURL.path)")
            return imageURL
        }
        
        // Try NSImage(named:) fallback - if successful, save to Documents for future use
        if let image = NSImage(named: resourceName) ?? NSImage(named: "images/\(resourceName)") {
            print("MYDEBUG →", "Found signature image via NSImage(named:), saving to Documents")
            // Save to Documents directory
            let imagesDir = documentsDirectory.appendingPathComponent("images")
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let destURL = imagesDir.appendingPathComponent(imageName)
            
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData) {
                let imageData: Data?
                if resourceType == "png" {
                    imageData = bitmapRep.representation(using: .png, properties: [:])
                } else {
                    imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                }
                
                if let data = imageData {
                    do {
                        try data.write(to: destURL)
                        print("MYDEBUG →", "Saved signature image to Documents: \(destURL.path)")
                        return destURL
                    } catch {
                        print("MYDEBUG →", "Failed to save signature image to Documents: \(error.localizedDescription)")
                        // Continue to other fallbacks
                    }
                }
            }
        }
        
        // Try app bundle resources
        if let bundleImageURL = Bundle.main.url(forResource: resourceName, withExtension: resourceType, subdirectory: "images") {
            if FileManager.default.fileExists(atPath: bundleImageURL.path) {
                print("MYDEBUG →", "Found signature image via bundle URL: \(bundleImageURL.path)")
                return bundleImageURL
            }
        }
        
        // Last resort: try to find in WindowReporter/images directory relative to bundle
        if let bundlePath = Bundle.main.resourcePath {
            let imagesPath = (bundlePath as NSString).appendingPathComponent("images")
            let fullImagePath = (imagesPath as NSString).appendingPathComponent(imageName)
            if FileManager.default.fileExists(atPath: fullImagePath) {
                print("MYDEBUG →", "Found signature image in resource path: \(fullImagePath)")
                return URL(fileURLWithPath: fullImagePath)
            }
        }
        
        // Final fallback: Try to use source images directory directly (skip copy due to sandbox restrictions)
        let sourceImagesPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/WindowReporter/WindowReporter/images/\(imageName)"
        
        if FileManager.default.fileExists(atPath: sourceImagesPath) && FileManager.default.isReadableFile(atPath: sourceImagesPath) {
            // Try to copy to Documents, but if it fails, use source directly
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let documentsImagesDir = docsDir.appendingPathComponent("images")
            let destURL = documentsImagesDir.appendingPathComponent(imageName)
            
            // Only try copy if destination doesn't exist
            if !FileManager.default.fileExists(atPath: destURL.path) {
                do {
                    try FileManager.default.createDirectory(at: documentsImagesDir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: sourceImagesPath), to: destURL)
                    print("MYDEBUG →", "Copied signature image from source to documents: \(destURL.path)")
                    return destURL
                } catch {
                    print("MYDEBUG →", "Failed to copy signature image (will use source): \(error.localizedDescription)")
                    // Fall through to use source directly
                }
            } else {
                // Destination already exists, use it
                print("MYDEBUG →", "Using existing signature image in documents: \(destURL.path)")
                return destURL
            }
            
            // Use source path directly as fallback (Mail.app should be able to access it)
            print("MYDEBUG →", "Using source signature image directly: \(sourceImagesPath)")
            return URL(fileURLWithPath: sourceImagesPath)
        }
        
        print("MYDEBUG →", "Warning: Could not find signature image file: \(imageName)")
        return nil
    }
    
    private func loadSignatureImageData() -> (Data, String) {
        // Detect current appearance
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua || 
                        NSApp.effectiveAppearance.name == .vibrantDark ||
                        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Get image path based on appearance
        let imageName = isDarkMode ? "TrueLogoDark.png" : "TrueLogoEmailLight.jpg"
        let mimeType = imageName.hasSuffix(".png") ? "image/png" : "image/jpeg"
        
        // Try to load from bundle/images directory
        let resourceName = imageName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "")
        let resourceType = imageName.hasSuffix(".png") ? "png" : "jpg"
        
        if let imagePath = Bundle.main.path(forResource: resourceName, ofType: resourceType, inDirectory: "images") {
            if let imageData = FileManager.default.contents(atPath: imagePath) {
                print("MYDEBUG →", "Loaded signature image from bundle: \(imagePath)")
                return (imageData, mimeType)
            }
        }
        
        // Fallback: try to load from documents directory or app bundle
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("images").appendingPathComponent(imageName)
        
        if FileManager.default.fileExists(atPath: imageURL.path),
           let imageData = FileManager.default.contents(atPath: imageURL.path) {
            print("MYDEBUG →", "Loaded signature image from documents: \(imageURL.path)")
            return (imageData, mimeType)
        }
        
        // Try app bundle resources
        if let bundleImageURL = Bundle.main.url(forResource: resourceName, withExtension: resourceType, subdirectory: "images"),
           let imageData = try? Data(contentsOf: bundleImageURL) {
            print("MYDEBUG →", "Loaded signature image from bundle URL: \(bundleImageURL.path)")
            return (imageData, mimeType)
        }
        
        // Last resort: try to find in WindowReporter/images directory relative to bundle
        if let bundlePath = Bundle.main.resourcePath {
            let imagesPath = (bundlePath as NSString).appendingPathComponent("images")
            let fullImagePath = (imagesPath as NSString).appendingPathComponent(imageName)
            
            if FileManager.default.fileExists(atPath: fullImagePath),
               let imageData = FileManager.default.contents(atPath: fullImagePath) {
                print("MYDEBUG →", "Loaded signature image from resource path: \(fullImagePath)")
                return (imageData, mimeType)
            }
        }
        
        // Final fallback: Try to copy from source images directory to Documents if it exists
        // This handles the case where images aren't in the bundle but are in the source code
        let sourceImagesPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/WindowReporter/WindowReporter/images/\(imageName)"
        if FileManager.default.fileExists(atPath: sourceImagesPath),
           let sourceImageData = FileManager.default.contents(atPath: sourceImagesPath) {
            // Copy to Documents for future use
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let documentsImagesDir = docsDir.appendingPathComponent("images")
            try? FileManager.default.createDirectory(at: documentsImagesDir, withIntermediateDirectories: true)
            let destURL = documentsImagesDir.appendingPathComponent(imageName)
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: sourceImagesPath), to: destURL)
            print("MYDEBUG →", "Loaded signature image from source and copied to Documents: \(sourceImagesPath)")
            return (sourceImageData, mimeType)
        }
        
        print("MYDEBUG →", "Warning: Could not load signature image: \(imageName)")
        return (Data(), mimeType) // Return empty data if image not found
    }
}

// MARK: - Report Customization Sheet (macOS)

struct ReportCustomizationSheetView: View {
    let job: Job
    @Binding var includeEngineeringLetter: Bool
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var editingCustomWeatherText: String = ""
    @State private var editingConclusionComment: String = ""
    @State private var editingIncludeEngineeringLetter: Bool = false
    @State private var imageRefreshId = UUID()
    @State private var showingReplaceOptionsForCustomHurricane = false
    @State private var showingFilePickerForCustomHurricane = false
    @State private var selectedPhotosItem: PhotosPickerItem?
    
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Custom Weather Image") {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasCustomHurricaneImage() {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            if let previewImage = loadCustomHurricaneImage() {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Current Image (double-click to replace)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Image(nsImage: previewImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 150)
                                        .cornerRadius(8)
                                        .overlay(
                                            Color.clear
                                                .contentShape(Rectangle())
                                                .onTapGesture(count: 2) {
                                                    showingReplaceOptionsForCustomHurricane = true
                                                }
                                        )
                                }
                                .id(imageRefreshId)
                            }
                            
                            Button(action: {
                                showingReplaceOptionsForCustomHurricane = true
                            }) {
                                HStack {
                                    Image(systemName: "photo")
                                    Text(hasCustomHurricaneImage() ? "Replace Image" : "Select Image")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            if hasCustomHurricaneImage() {
                                Button(action: {
                                    removeCustomHurricaneImage()
                                    imageRefreshId = UUID()
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Remove")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox("Custom Weather Text") {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasCustomWeatherText() {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom weather text")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextEditor(text: $editingCustomWeatherText)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(Color(.controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                    )
                            }
                            Text("Leave empty to use default weather text")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if hasCustomWeatherText() {
                                Button(action: {
                                    editingCustomWeatherText = ""
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Reset to Default")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox("Conclusion Comment") {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasConclusionComment() {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Comment for PDF")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextEditor(text: $editingConclusionComment)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(Color(.controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                    )
                            }
                            Text("This comment appears as a separate paragraph in the PDF between the conclusion and 'not tested windows' section")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if hasConclusionComment() {
                                Button(action: {
                                    editingConclusionComment = ""
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear Comment")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding()
                    }
                    
                    GroupBox("Engineering Letter") {
                        Toggle("Include Engineering Letter", isOn: $editingIncludeEngineeringLetter)
                            .padding()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Report Customization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: handleCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: handleSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadInitialValues()
        }
        .sheet(isPresented: $showingReplaceOptionsForCustomHurricane) {
            ReplaceImageOptionsSheet(
                selectedPhotosItem: $selectedPhotosItem,
                onFileSelected: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingFilePickerForCustomHurricane = true
                    }
                },
                onCancel: { }
            )
        }
        .fileImporter(
            isPresented: $showingFilePickerForCustomHurricane,
            allowedContentTypes: [.jpeg, .png, .heic, .tiff, .bmp, .gif],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let image = NSImage(contentsOf: url) {
                    saveCustomHurricaneImage(image, for: job)
                    imageRefreshId = UUID()
                }
            case .failure(let error):
                print("MYDEBUG →", "File picker error: \(error.localizedDescription)")
            }
        }
        .onChange(of: selectedPhotosItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        saveCustomHurricaneImage(nsImage, for: job)
                        selectedPhotosItem = nil
                        imageRefreshId = UUID()
                    }
                }
            }
        }
    }
    
    private func loadInitialValues() {
        editingCustomWeatherText = job.customWeatherText ?? ""
        editingConclusionComment = job.conclusionComment ?? ""
        editingIncludeEngineeringLetter = job.includeEngineeringLetter ?? false
    }
    
    private func hasCustomHurricaneImage() -> Bool {
        guard let imagePath = job.customHurricaneImagePath else { return false }
        return loadCustomHurricaneImage(from: imagePath) != nil
    }
    
    private func loadCustomHurricaneImage() -> NSImage? {
        guard let imagePath = job.customHurricaneImagePath else { return nil }
        return loadCustomHurricaneImage(from: imagePath)
    }
    
    private func loadCustomHurricaneImage(from imagePath: String) -> NSImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("custom_hurricane_images").appendingPathComponent(imagePath)
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            return nil
        }
        
        return NSImage(contentsOf: imageURL)
    }
    
    private func hasCustomWeatherText() -> Bool {
        guard let text = job.customWeatherText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func hasConclusionComment() -> Bool {
        guard let comment = job.conclusionComment else { return false }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func removeCustomHurricaneImage() {
        if let imagePath = job.customHurricaneImagePath {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("custom_hurricane_images").appendingPathComponent(imagePath)
            try? FileManager.default.removeItem(at: imageURL)
        }
        
        job.customHurricaneImagePath = nil
        
        do {
            try viewContext.save()
        } catch {
            print("MYDEBUG →", "Failed to remove custom hurricane image: \(error.localizedDescription)")
        }
    }
    
    private func handleSave() {
        let trimmedWeatherText = editingCustomWeatherText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedWeatherText.isEmpty {
            job.customWeatherText = nil
        } else {
            job.customWeatherText = editingCustomWeatherText
        }
        
        let trimmedComment = editingConclusionComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedComment.isEmpty {
            job.conclusionComment = nil
        } else {
            job.conclusionComment = editingConclusionComment
        }
        
        job.includeEngineeringLetter = editingIncludeEngineeringLetter
        includeEngineeringLetter = editingIncludeEngineeringLetter
        
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
            onSave()
        } catch {
            print("MYDEBUG →", "Failed to save customization: \(error.localizedDescription)")
        }
    }
    
    private func handleCancel() {
        onCancel()
    }
    
    private func saveCustomHurricaneImage(_ image: NSImage, for job: Job) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("MYDEBUG →", "Failed to convert custom hurricane image to JPEG data")
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("custom_hurricane_images")
        
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            
            let fileName = "\(job.jobId ?? UUID().uuidString)_custom_hurricane.jpg"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            
            try imageData.write(to: fileURL)
            job.customHurricaneImagePath = fileName
            
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: job)
        } catch {
            print("MYDEBUG →", "Failed to save custom hurricane image: \(error.localizedDescription)")
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

// MARK: - JobStatusBadge

struct JobStatusBadge: View {
    let status: JobStatus
    var iconOnly: Bool = false
    
    var body: some View {
        if iconOnly {
            Image(systemName: status.icon)
                .font(.caption)
                .foregroundColor(statusColor)
                .padding(6)
                .background(statusColor.opacity(0.2))
                .clipShape(Circle())
        } else {
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.caption2)
                Text(status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .newImport:
            return .blue
        case .inProgress:
            return .orange
        case .tested:
            return .green
        case .reportDelivered:
            return .purple
        case .backedUpToArchive:
            return .gray
        }
    }
}

// MARK: - Replace Image Options Sheet (choose from Photos or File)
private struct ReplaceImageOptionsSheet: View {
    @Binding var selectedPhotosItem: PhotosPickerItem?
    let onFileSelected: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Replace Image")
                .font(.headline)
            PhotosPicker(selection: $selectedPhotosItem, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
            Button(action: onFileSelected) {
                Label("Choose from File", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.borderless)
        }
        .padding(24)
        .frame(minWidth: 280)
    }
}

#Preview {
    JobDetailView(job: Job(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

