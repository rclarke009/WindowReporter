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
        }
    }
}

struct OverheadCanvasView: View {
    let job: Job
    
    var body: some View {
        VStack {
            if let imagePath = job.overheadImagePath {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let imageURL = documentsDirectory.appendingPathComponent("overhead_images").appendingPathComponent(imagePath)
                
                if let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Could not load overhead image")
                        .foregroundColor(.secondary)
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
        .padding()
    }
}

struct ExportView: View {
    let job: Job
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Export Report")
                .font(.title2)
            Text("Export functionality will be available here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

