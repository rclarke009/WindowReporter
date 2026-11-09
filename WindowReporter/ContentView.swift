//
//  ContentView.swift
//  WindowReporter
//
//  Created for macOS ReportWriter app
//

import SwiftUI
import CoreData
import AppKit

/// Sort order for the jobs list. Persisted via AppStorage.
enum JobSortOrder: String, CaseIterable {
    case newestFirst = "newestFirst"
    case alphabetical = "alphabetical"
}

/// Filter for jobs list by status (matches iOS).
enum JobListFilter: String, CaseIterable {
    case inProgress
    case delivered
    case archived
}

struct ContentView: View {
    // Connection test comment.
    // UserDefaults key for storing last selected job
    private let lastSelectedJobKey = "lastSelectedJobId"
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingImportSheet = false
    @State private var showingCreateJobSheet = false
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow
    @State private var selectedJob: Job?
    @State private var showingDeleteConfirmation = false
    @State private var jobsToDelete: [Job] = []
    @State private var sidebarRefreshId = UUID()
    @AppStorage("jobsSortOrder") private var jobsSortOrderRaw: String = JobSortOrder.newestFirst.rawValue
    @AppStorage("jobsListFilter") private var selectedFilterRaw: String = JobListFilter.inProgress.rawValue
    @State private var isExportingAllJobs = false
    @State private var exportProgress: Double = 0.0
    @State private var currentExportingJob: String?
    @State private var allJobsExportError: String?
    @State private var currentExportScopeTitle = "All Reports"
    @State private var showingCoreDataLoadError = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Job.createdAt, ascending: false)],
        animation: .default)
    private var jobs: FetchedResults<Job>

    private var jobsSortOrder: JobSortOrder {
        get { JobSortOrder(rawValue: jobsSortOrderRaw) ?? .newestFirst }
        set { jobsSortOrderRaw = newValue.rawValue }
    }

    /// Jobs list for display; order depends on user preference.
    private var sortedJobs: [Job] {
        let order = jobsSortOrder
        if order == .newestFirst {
            return Array(jobs)
        }
        return jobs.sorted { j1, j2 in
            let c1 = (j1.clientName ?? "").lowercased()
            let c2 = (j2.clientName ?? "").lowercased()
            if c1 != c2 { return c1 < c2 }
            return (j1.jobId ?? "") < (j2.jobId ?? "")
        }
    }

    private var selectedFilter: JobListFilter {
        get { JobListFilter(rawValue: selectedFilterRaw) ?? .inProgress }
        set { selectedFilterRaw = newValue.rawValue }
    }

    /// Jobs list filtered by status tab (In Progress / Delivered / Archived).
    private var filteredJobs: [Job] {
        let filter = selectedFilter
        switch filter {
        case .inProgress:
            return sortedJobs.filter { job in
            let status = job.currentStatus
            return status == .newImport || status == .inProgress || status == .tested
            }
        case .delivered:
            return sortedJobs.filter { job in job.currentStatus == .reportDelivered }
        case .archived:
            return sortedJobs.filter { job in job.currentStatus == .backedUpToArchive }
        }
    }

    private var inProgressJobs: [Job] {
        sortedJobs.filter { job in
            let status = job.currentStatus
            return status == .newImport || status == .inProgress || status == .tested
        }
    }

    private var deliveredJobs: [Job] {
        sortedJobs.filter { job in job.currentStatus == .reportDelivered }
    }

    private var archivedJobs: [Job] {
        sortedJobs.filter { job in job.currentStatus == .backedUpToArchive }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                jobs: filteredJobs,
                sidebarRefreshId: sidebarRefreshId,
                jobsListFilterRaw: $selectedFilterRaw,
                isFullListEmpty: sortedJobs.isEmpty,
                jobsSortOrderRaw: $jobsSortOrderRaw,
                selectedJob: $selectedJob,
                showingImportSheet: $showingImportSheet,
                showingCreateJobSheet: $showingCreateJobSheet,
                onDelete: deleteJobs,
                jobsToDelete: $jobsToDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                allJobs: sortedJobs,
                inProgressJobs: inProgressJobs,
                deliveredJobs: deliveredJobs,
                archivedJobs: archivedJobs,
                onExportJobs: exportJobs
            )
        } detail: {
            if let selectedJob = selectedJob {
                JobDetailView(job: selectedJob, showingSettings: $showingSettings)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a Job")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Choose a job from the list to view details and work on reports")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Job Details")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportJobsView()
        }
        .sheet(isPresented: $showingCreateJobSheet) {
            CreateJobView()
        }
        .alert("Delete Job\(jobsToDelete.count > 1 ? "s" : "")", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                jobsToDelete = []
            }
            Button("Delete", role: .destructive) {
                confirmDeleteJobs()
            }
        } message: {
            if jobsToDelete.count == 1 {
                Text("Are you sure you want to delete job \(jobsToDelete.first?.jobId ?? "Unknown")? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(jobsToDelete.count) jobs? This action cannot be undone.")
            }
        }
        .onChange(of: showingSettings) { _, isShowing in
            guard isShowing else { return }
            openWindow(id: "settings")
            showingSettings = false
        }
        .onAppear {
            // Try to restore the last selected job from UserDefaults
            if selectedJob == nil && !jobs.isEmpty {
                if let savedJobId = UserDefaults.standard.string(forKey: lastSelectedJobKey),
                   let savedJob = jobs.first(where: { $0.jobId == savedJobId }) {
                    selectedJob = savedJob
                    print("Restored last selected job: \(savedJobId)")
                } else {
                    // Fall back to the most recently added job
                    selectedJob = jobs.first
                    print("No saved job found, selecting most recent job")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newJobCreated)) { notification in
            // Auto-select newly created job
            if let newJob = notification.object as? Job {
                selectedJob = newJob
                // Save the new job ID to UserDefaults
                if let jobId = newJob.jobId {
                    UserDefaults.standard.set(jobId, forKey: lastSelectedJobKey)
                    print("Saved new job selection: \(jobId)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewJob)) { _ in
            showingCreateJobSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupAllJobsRequested)) { _ in
            exportJobs(Array(jobs), scopeTitle: "All Reports")
        }
        .overlay {
            if isExportingAllJobs {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Backing up \(currentExportScopeTitle)...")
                            .font(.headline)
                            .foregroundColor(.white)
                        if let currentJob = currentExportingJob {
                            Text("Processing: \(currentJob)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        ProgressView(value: exportProgress)
                            .frame(width: 250)
                        Text("\(Int(exportProgress * 100))%")
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(30)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .onAppear {
            showingCoreDataLoadError = PersistenceController.shared.loadError != nil
        }
        .alert("Database Error", isPresented: $showingCoreDataLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = PersistenceController.shared.loadError {
                Text(error.localizedDescription)
            }
        }
        .alert("Backup Failed", isPresented: Binding(
            get: { allJobsExportError != nil },
            set: { if !$0 { allJobsExportError = nil } }
        )) {
            Button("OK", role: .cancel) { allJobsExportError = nil }
        } message: {
            if let error = allJobsExportError {
                Text(error)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobDataUpdated)) { notification in
            if let updatedJob = notification.object as? Job {
                DispatchQueue.main.async {
                    viewContext.refresh(updatedJob, mergeChanges: true)
                    sidebarRefreshId = UUID()
                }
            } else {
                sidebarRefreshId = UUID()
            }
        }
    }

    private func deleteJobs(offsets: IndexSet) {
        let jobsToDeleteArray = offsets.map { filteredJobs[$0] }
        jobsToDelete = jobsToDeleteArray
        showingDeleteConfirmation = true
    }
    
    private func confirmDeleteJobs() {
        withAnimation {
            // Check if the currently selected job is being deleted
            for job in jobsToDelete {
                if job == selectedJob {
                    selectedJob = nil
                    // Clear the saved job ID from UserDefaults
                    UserDefaults.standard.removeObject(forKey: lastSelectedJobKey)
                    print("Cleared UserDefaults for deleted selected job")
                }
            }
            
            jobsToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
            
            jobsToDelete = []
        }
    }

    private func exportJobs(_ jobsToExport: [Job], scopeTitle: String) {
        guard !jobsToExport.isEmpty else { return }
        guard !isExportingAllJobs else { return }

        isExportingAllJobs = true
        exportProgress = 0.0
        currentExportingJob = nil
        allJobsExportError = nil
        currentExportScopeTitle = scopeTitle

        Task {
            do {
                let exporter = BulkJobsExporter(jobs: jobsToExport)
                exporter.onProgress = { currentIndex, totalJobs, jobName in
                    DispatchQueue.main.async {
                        self.currentExportingJob = jobName
                        self.exportProgress = Double(currentIndex + 1) / Double(totalJobs)
                    }
                }

                let zipURL = try await exporter.exportAllJobs()

                await MainActor.run {
                    self.markJobsBackedUpToArchive(jobsToExport)
                    self.isExportingAllJobs = false
                    self.exportProgress = 1.0
                    self.currentExportingJob = nil
                    self.presentBackupShareSheet(for: zipURL)
                }
            } catch {
                print("MYDEBUG →", "Bulk export failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.allJobsExportError = error.localizedDescription
                    self.isExportingAllJobs = false
                    self.currentExportingJob = nil
                }
            }
        }
    }

    private func markJobsBackedUpToArchive(_ jobsToMark: [Job]) {
        guard !jobsToMark.isEmpty else { return }
        for job in jobsToMark {
            job.markBackedUpToArchive()
        }
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: .jobDataUpdated, object: nil)
            print("MYDEBUG →", "Marked \(jobsToMark.count) job(s) as archived after backup")
        } catch {
            print("MYDEBUG →", "Failed to mark jobs archived after backup: \(error.localizedDescription)")
        }
    }

    private func presentBackupShareSheet(for url: URL) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Jobs Backup"
        savePanel.nameFieldStringValue = url.lastPathComponent
        savePanel.directoryURL = url.deletingLastPathComponent()
        savePanel.canCreateDirectories = true
        savePanel.begin { response in
            guard response == .OK, let destination = savePanel.url else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                print("MYDEBUG →", "Failed to copy backup ZIP: \(error.localizedDescription)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

struct SidebarView: View {
    let jobs: [Job]
    let sidebarRefreshId: UUID
    @Binding var jobsListFilterRaw: String
    let isFullListEmpty: Bool
    @Binding var jobsSortOrderRaw: String
    @Binding var selectedJob: Job?
    @Binding var showingImportSheet: Bool
    @Binding var showingCreateJobSheet: Bool
    let onDelete: (IndexSet) -> Void
    @Binding var jobsToDelete: [Job]
    @Binding var showingDeleteConfirmation: Bool
    let allJobs: [Job]
    let inProgressJobs: [Job]
    let deliveredJobs: [Job]
    let archivedJobs: [Job]
    let onExportJobs: ([Job], String) -> Void
    @Environment(\.managedObjectContext) private var viewContext

    private var jobsSortOrder: JobSortOrder {
        JobSortOrder(rawValue: jobsSortOrderRaw) ?? .newestFirst
    }

    private var selectedFilter: JobListFilter {
        get { JobListFilter(rawValue: jobsListFilterRaw) ?? .inProgress }
        set { jobsListFilterRaw = newValue.rawValue }
    }

    private var selectedFilterBinding: Binding<JobListFilter> {
        Binding(
            get: { JobListFilter(rawValue: jobsListFilterRaw) ?? .inProgress },
            set: { jobsListFilterRaw = $0.rawValue }
        )
    }

    private var emptyFilterMessage: String {
        switch selectedFilter {
        case .inProgress: return "No In Progress jobs"
        case .delivered: return "No Delivered jobs"
        case .archived: return "No Archived jobs"
        }
    }
    
    var body: some View {
        Group {
            if isFullListEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Jobs Available")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Create a new job or import a Job Intake Package to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Button("Create Job") {
                            showingCreateJobSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Import Jobs") {
                            showingImportSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Picker("Filter by Status", selection: selectedFilterBinding) {
                        Text("In Progress").tag(JobListFilter.inProgress)
                        Text("Delivered").tag(JobListFilter.delivered)
                        Text("Archived").tag(JobListFilter.archived)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if jobs.isEmpty {
                        VStack(spacing: 12) {
                            Text(emptyFilterMessage)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $selectedJob) {
                            ForEach(jobs) { job in
                                JobRowView(job: job)
                                    .tag(job)
                                    .contextMenu {
                                        Button(role: .destructive, action: {
                                            jobsToDelete = [job]
                                            showingDeleteConfirmation = true
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            .onDelete(perform: onDelete)
                        }
                    }
                }
            }
        }
        .id(sidebarRefreshId)
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingCreateJobSheet = true
                }) {
                    Label("Create Job", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showingImportSheet = true
                }) {
                    Label("Import Jobs", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Backup All Jobs (\(allJobs.count))") {
                        onExportJobs(allJobs, "All Reports")
                    }
                    Divider()
                    Button("In Progress (\(inProgressJobs.count))") {
                        onExportJobs(inProgressJobs, "In Progress")
                    }
                    Button("Delivered (\(deliveredJobs.count))") {
                        onExportJobs(deliveredJobs, "Delivered")
                    }
                    Button("Archived (\(archivedJobs.count))") {
                        onExportJobs(archivedJobs, "Archived")
                    }
                } label: {
                    Label("Backup Jobs", systemImage: "archivebox")
                }
                .disabled(allJobs.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                if selectedJob != nil {
                    Button(role: .destructive, action: {
                        if let job = selectedJob {
                            jobsToDelete = [job]
                            showingDeleteConfirmation = true
                        }
                    }) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(action: { jobsSortOrderRaw = JobSortOrder.newestFirst.rawValue }) {
                        Label("Newest first", systemImage: jobsSortOrder == .newestFirst ? "checkmark.circle.fill" : "circle")
                    }
                    Button(action: { jobsSortOrderRaw = JobSortOrder.alphabetical.rawValue }) {
                        Label("Alphabetical (A–Z)", systemImage: jobsSortOrder == .alphabetical ? "checkmark.circle.fill" : "circle")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                }
                .help("Sort jobs list")
            }
        }
    }
}

// Helper: street address only (for job row title)
private func formatAddressLine1(job: Job) -> String {
    let addressToUse = job.cleanedAddressLine1 ?? job.addressLine1 ?? ""
    return addressToUse.isEmpty ? "No address" : addressToUse
}

// Helper: city, state zip on one line
private func formatCityStateZip(job: Job) -> String {
    var cityStateZip: [String] = []
    if let city = job.city, !city.isEmpty {
        cityStateZip.append(city)
    }
    if let state = job.state, !state.isEmpty {
        cityStateZip.append(state)
    }
    if let zip = job.zip, !zip.isEmpty {
        cityStateZip.append(zip)
    }
    return cityStateZip.isEmpty ? "" : cityStateZip.joined(separator: ", ")
}

// Helper function to format full address with proper handling of missing components
private func formatAddress(job: Job) -> String {
    let line1 = formatAddressLine1(job: job)
    let csz = formatCityStateZip(job: job)
    if csz.isEmpty { return line1 }
    return "\(line1), \(csz)"
}

struct JobRowView: View {
    let job: Job
    
    // Helper function to filter out Window Test Status and Roof Report Status from notes
    private func filteredNotes(_ notes: String?) -> String? {
        guard let notes = notes, !notes.isEmpty else { return nil }
        
        // Split by newlines and filter out lines containing status information
        let lines = notes.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let lowercased = line.lowercased()
            return !lowercased.contains("window test status") && 
                   !lowercased.contains("roof report status")
        }
        
        let filtered = filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title: address (slightly larger bold)
            Text(formatAddressLine1(job: job))
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(2)
            
            // City, state zip — small
            if !formatCityStateZip(job: job).isEmpty {
                Text(formatCityStateZip(job: job))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Report number — small
            if let jobId = job.jobId, jobId.count >= 13 {
                Text(String(jobId.suffix(13)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(job.jobId ?? "Unknown Job")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Notes (if any) — filtered
            if let filteredNotes = filteredNotes(job.notes), !filteredNotes.isEmpty {
                Text(filteredNotes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Windows count and date — as before
            if let windows = job.windows?.allObjects as? [Window] {
                HStack {
                    Image(systemName: "square.grid.3x3")
                        .foregroundColor(.secondary)
                    Text("\(windows.count) windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let updatedAt = job.updatedAt {
                        Text(updatedAt, formatter: dateFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch status {
        case "Ready":
            return .blue
        case "In Progress":
            return .orange
        case "Completed":
            return .green
        case "Failed":
            return .red
        case "Pass":
            return .green
        case "Fail":
            return .red
        case "Inaccessible", "Not Tested":
            return .gray
        case "Pending":
            return .blue
        default:
            return .gray
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
