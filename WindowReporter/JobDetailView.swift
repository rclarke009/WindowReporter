//
//  JobDetailView.swift
//  WindowReporter
//
//  macOS version - basic structure
//

import SwiftUI
import CoreData
import AppKit

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
        }
        .navigationTitle("Job Details")
        .sheet(isPresented: $showingEditJob) {
            EditJobView(job: job)
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobDataUpdated)) { _ in
            // Refresh view when job data is updated
        }
    }
}

struct JobOverviewView: View {
    let job: Job
    
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
                
                // Overhead Image (Overview Photo)
                if let imagePath = job.overheadImagePath {
                    GroupBox("Overhead Image / Overview Photo") {
                        if let image = loadOverheadImage(from: imagePath) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
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
            .padding()
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
            .padding()
        }
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
                            StatusBadge(status: "Inaccessible")
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

struct OverheadCanvasView: View {
    let job: Job
    @State private var image: NSImage?
    @State private var imageSize: CGSize = .zero
    
    private var windows: [Window] {
        guard let windowsSet = job.windows else { return [] }
        return (windowsSet.allObjects as? [Window] ?? []).sorted { ($0.windowNumber ?? "") < ($1.windowNumber ?? "") }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.controlBackgroundColor)
                    .ignoresSafeArea()
                
                if let image = image {
                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .background(
                                    GeometryReader { imageGeometry in
                                        Color.clear
                                            .onAppear {
                                                // Calculate displayed image size based on aspect ratio
                                                let frameSize = imageGeometry.size
                                                let imageAspectRatio = image.size.width / image.size.height
                                                let frameAspectRatio = frameSize.width / frameSize.height
                                                
                                                if imageAspectRatio > frameAspectRatio {
                                                    // Image is wider - letterboxed
                                                    let displayedHeight = frameSize.width / imageAspectRatio
                                                    imageSize = CGSize(width: frameSize.width, height: displayedHeight)
                                                } else {
                                                    // Image is taller - pillarboxed
                                                    let displayedWidth = frameSize.height * imageAspectRatio
                                                    imageSize = CGSize(width: displayedWidth, height: frameSize.height)
                                                }
                                            }
                                    }
                                )
                            
                            // Window dots overlay
                            if imageSize.width > 0 && imageSize.height > 0 {
                                ForEach(windows, id: \.objectID) { window in
                                    WindowDotView(
                                        window: window,
                                        imageSize: imageSize,
                                        originalImageSize: image.size,
                                        viewSize: geometry.size
                                    )
                                }
                            }
                        }
                        .frame(
                            width: max(geometry.size.width, imageSize.width),
                            height: max(geometry.size.height, imageSize.height)
                        )
                    }
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
        }
        .onChange(of: job.overheadImagePath) { _, _ in
            loadImage()
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

struct ExportView: View {
    let job: Job
    @State private var isExportingDocx = false
    @State private var docxError: String?
    @State private var docxFileURL: URL?
    @State private var isExportingPdf = false
    @State private var pdfError: String?
    @State private var pdfFileURL: URL?
    
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
                    }
                    .padding()
                }
            }
            .padding()
        }
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
        
        Task {
            do {
                let package = FieldResultsPackage(job: job, exportDirectory: URL(fileURLWithPath: ""))
                let pdfURL = try await package.exportPDFReport()
                await MainActor.run {
                    pdfFileURL = pdfURL
                    isExportingPdf = false
                    // Open the file location
                    NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
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
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

#Preview {
    JobDetailView(job: Job(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

