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

enum RecipientType: String, CaseIterable {
    case mrLevy = "Mr. Levy"
    case dynamicClient = "Dynamic Client Name"
}

enum ReportSelectionMode: String, CaseIterable {
    case generateNew = "Generate New Report"
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
            .padding()
        }
        .onAppear {
            updateEmailAddress(for: recipientType)
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
    
    private func exportFullJobPackage() {
        guard !isExportingFullPackage else { return }
        isExportingFullPackage = true
        fullPackageError = nil
        fullPackageFileURL = nil
        
        Task {
            do {
                let exporter = FullJobPackageExporter(job: job)
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
                    let package = FieldResultsPackage(job: job, exportDirectory: URL(fileURLWithPath: ""))
                    pdfURL = try await package.exportPDFReport()
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
        let logPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/.cursor/debug.log"
        
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
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1160", "message": "Signature image URL loaded", "data": ["signatureImageURL": signatureImageURL?.path ?? "nil", "signatureImageName": signatureImageURL?.lastPathComponent ?? "nil"], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        // Create email body - try using NSAttributedString with HTML for better image support
        let emailBody: Any
        var usingBase64 = false
        var imageDataSize: Int = 0
        
        if let signatureURL = signatureImageURL {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "A,B", "location": "JobDetailView.swift:1176", "message": "Signature URL found", "data": ["signatureURL": signatureURL.path], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            
            // Load image data and embed as base64 (more reliable than CID for Mail.app)
            // Resize image to reasonable size for email (max 300px width)
            if let nsImage = NSImage(contentsOf: signatureURL) {
                let originalSize = nsImage.size
                imageDataSize = (try? Data(contentsOf: signatureURL))?.count ?? 0
                
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "C,D", "location": "JobDetailView.swift:1195", "message": "Image loaded", "data": ["imageDataSize": imageDataSize, "imageWidth": originalSize.width, "imageHeight": originalSize.height], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                    FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write((logStr + "\n").data(using: .utf8)!)
                        handle.closeFile()
                    }
                }
                // #endregion
                
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
        
        // #region agent log
        let emailBodyType = type(of: emailBody)
        let emailBodyString = emailBody as? String ?? "not a string"
        let imgTagCount = emailBodyString.components(separatedBy: "<img").count - 1
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "A", "location": "JobDetailView.swift:1195", "message": "Email body created", "data": ["emailBodyType": String(describing: emailBodyType), "usingBase64": usingBase64, "imgTagCount": imgTagCount, "emailBodyLength": emailBodyString.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        // Set email properties
        emailService.recipients = [recipientEmail]
        emailService.subject = "Window Test Report - \(address)"
        
        // Prepare items: HTML body and PDF report
        // Note: If using base64, we don't need to attach the image separately
        var items: [Any] = [emailBody, pdfURL]
        
        // Only attach image separately if using CID reference (NOT base64)
        let willAttachImage = signatureImageURL != nil && !usingBase64
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1205", "message": "Items preparation", "data": ["willAttachImage": willAttachImage, "itemsCount": items.count, "usingBase64": usingBase64, "signatureImageURL": signatureImageURL != nil], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if willAttachImage {
            items.append(signatureImageURL!)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1260", "message": "Image attached separately", "data": ["itemsCountAfterAppend": items.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
        }
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1215", "message": "Final items count", "data": ["finalItemsCount": items.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
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
        let logPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/.cursor/debug.log"
        
        // Detect current appearance
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua || 
                        NSApp.effectiveAppearance.name == .vibrantDark ||
                        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Get image path based on appearance
        let imageName = isDarkMode ? "TrueLogoDark.png" : "TrueLogoEmailLight.jpg"
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "A", "location": "JobDetailView.swift:1216", "message": "loadSignatureImageURL entry", "data": ["isDarkMode": isDarkMode, "imageName": imageName], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        // Try to load from bundle/images directory
        let resourceName = imageName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "")
        let resourceType = imageName.hasSuffix(".png") ? "png" : "jpg"
        
        // #region agent log
        let bundleResourcePath = Bundle.main.resourcePath ?? "nil"
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "B", "location": "JobDetailView.swift:1235", "message": "Bundle check", "data": ["bundleResourcePath": bundleResourcePath, "resourceName": resourceName, "resourceType": resourceType], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if let imagePath = Bundle.main.path(forResource: resourceName, ofType: resourceType, inDirectory: "images") {
            let fileExists = FileManager.default.fileExists(atPath: imagePath)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "B", "location": "JobDetailView.swift:1242", "message": "Bundle path result", "data": ["imagePath": imagePath, "fileExists": fileExists], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            if fileExists {
                print("MYDEBUG →", "Found signature image in bundle: \(imagePath)")
                return URL(fileURLWithPath: imagePath)
            }
        }
        
        // Priority 1: Try to load from documents directory (most reliable)
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("images").appendingPathComponent(imageName)
        
        let docsExists = FileManager.default.fileExists(atPath: imageURL.path)
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "C", "location": "JobDetailView.swift:1255", "message": "Documents check", "data": ["imageURL": imageURL.path, "fileExists": docsExists], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if docsExists {
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
            let bundleURLExists = FileManager.default.fileExists(atPath: bundleImageURL.path)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "D", "location": "JobDetailView.swift:1268", "message": "Bundle URL check", "data": ["bundleImageURL": bundleImageURL.path, "fileExists": bundleURLExists], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            if bundleURLExists {
                print("MYDEBUG →", "Found signature image via bundle URL: \(bundleImageURL.path)")
                return bundleImageURL
            }
        }
        
        // Last resort: try to find in WindowReporter/images directory relative to bundle
        if let bundlePath = Bundle.main.resourcePath {
            let imagesPath = (bundlePath as NSString).appendingPathComponent("images")
            let fullImagePath = (imagesPath as NSString).appendingPathComponent(imageName)
            let resourcePathExists = FileManager.default.fileExists(atPath: fullImagePath)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1280", "message": "Resource path check", "data": ["bundlePath": bundlePath, "imagesPath": imagesPath, "fullImagePath": fullImagePath, "fileExists": resourcePathExists], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            if resourcePathExists {
                print("MYDEBUG →", "Found signature image in resource path: \(fullImagePath)")
                return URL(fileURLWithPath: fullImagePath)
            }
        }
        
        // Final fallback: Try to use source images directory directly (skip copy due to sandbox restrictions)
        let sourceImagesPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/WindowReporter/WindowReporter/images/\(imageName)"
        
        // #region agent log
        let sourceExists = FileManager.default.fileExists(atPath: sourceImagesPath)
        let sourceReadable = FileManager.default.isReadableFile(atPath: sourceImagesPath)
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "JobDetailView.swift:1295", "message": "Source file check", "data": ["sourceImagesPath": sourceImagesPath, "sourceExists": sourceExists, "sourceReadable": sourceReadable, "imageName": imageName], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if sourceExists && sourceReadable {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "JobDetailView.swift:1305", "message": "Using source file", "data": ["sourceImagesPath": sourceImagesPath], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
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
        let logPath = "/Users/rebeccaclarke/Documents/Public/JW Roofing/VenShares/Projects/WindowTestApp/WindowTest2/.cursor/debug.log"
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "A", "location": "JobDetailView.swift:1198", "message": "loadSignatureImageData entry", "data": ["timestamp": Date().timeIntervalSince1970], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        // Detect current appearance
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua || 
                        NSApp.effectiveAppearance.name == .vibrantDark ||
                        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Get image path based on appearance
        let imageName = isDarkMode ? "TrueLogoDark.png" : "TrueLogoEmailLight.jpg"
        let mimeType = imageName.hasSuffix(".png") ? "image/png" : "image/jpeg"
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "A", "location": "JobDetailView.swift:1205", "message": "Image selection", "data": ["isDarkMode": isDarkMode, "imageName": imageName, "mimeType": mimeType], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        // Try to load from bundle/images directory
        let resourceName = imageName.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: "")
        let resourceType = imageName.hasSuffix(".png") ? "png" : "jpg"
        
        // #region agent log
        let bundleResourcePath = Bundle.main.resourcePath ?? "nil"
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "B", "location": "JobDetailView.swift:1215", "message": "Bundle paths check", "data": ["bundleResourcePath": bundleResourcePath, "resourceName": resourceName, "resourceType": resourceType, "inDirectory": "images"], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if let imagePath = Bundle.main.path(forResource: resourceName, ofType: resourceType, inDirectory: "images") {
            // #region agent log
            let fileExists = FileManager.default.fileExists(atPath: imagePath)
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "B", "location": "JobDetailView.swift:1220", "message": "Bundle path found", "data": ["imagePath": imagePath, "fileExists": fileExists], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            if let imageData = FileManager.default.contents(atPath: imagePath) {
                print("MYDEBUG →", "Loaded signature image from bundle: \(imagePath)")
                return (imageData, mimeType)
            }
        }
        
        // Fallback: try to load from documents directory or app bundle
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("images").appendingPathComponent(imageName)
        
        // #region agent log
        let fileExistsDocs = FileManager.default.fileExists(atPath: imageURL.path)
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "C", "location": "JobDetailView.swift:1235", "message": "Documents directory check", "data": ["imageURL": imageURL.path, "fileExists": fileExistsDocs], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        if FileManager.default.fileExists(atPath: imageURL.path),
           let imageData = FileManager.default.contents(atPath: imageURL.path) {
            print("MYDEBUG →", "Loaded signature image from documents: \(imageURL.path)")
            return (imageData, mimeType)
        }
        
        // Try app bundle resources
        if let bundleImageURL = Bundle.main.url(forResource: resourceName, withExtension: resourceType, subdirectory: "images"),
           let imageData = try? Data(contentsOf: bundleImageURL) {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "D", "location": "JobDetailView.swift:1245", "message": "Bundle URL found", "data": ["bundleImageURL": bundleImageURL.path], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            print("MYDEBUG →", "Loaded signature image from bundle URL: \(bundleImageURL.path)")
            return (imageData, mimeType)
        }
        
        // Last resort: try to find in WindowReporter/images directory relative to bundle
        if let bundlePath = Bundle.main.resourcePath {
            let imagesPath = (bundlePath as NSString).appendingPathComponent("images")
            let fullImagePath = (imagesPath as NSString).appendingPathComponent(imageName)
            
            // #region agent log
            let fileExistsRes = FileManager.default.fileExists(atPath: fullImagePath)
            if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "E", "location": "JobDetailView.swift:1255", "message": "Resource path check", "data": ["bundlePath": bundlePath, "imagesPath": imagesPath, "fullImagePath": fullImagePath, "fileExists": fileExistsRes], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
                FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((logStr + "\n").data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            // #endregion
            
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
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: ["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "JobDetailView.swift:1265", "message": "All paths failed", "data": ["imageName": imageName], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)]), let logStr = String(data: logData, encoding: .utf8) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((logStr + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        // #endregion
        
        print("MYDEBUG →", "Warning: Could not load signature image: \(imageName)")
        return (Data(), mimeType) // Return empty data if image not found
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

