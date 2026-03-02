//
//  ContentView.swift
//  WindowReporter
//
//  Created for macOS ReportWriter app
//

import SwiftUI
import CoreData

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
    // UserDefaults key for storing last selected job
    private let lastSelectedJobKey = "lastSelectedJobId"
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingImportSheet = false
    @State private var showingCreateJobSheet = false
    @State private var showingSettings = false
    @State private var selectedJob: Job?
    @State private var showingDeleteConfirmation = false
    @State private var jobsToDelete: [Job] = []
    @AppStorage("jobsSortOrder") private var jobsSortOrderRaw: String = JobSortOrder.newestFirst.rawValue
    @AppStorage("jobsListFilter") private var selectedFilterRaw: String = JobListFilter.inProgress.rawValue

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

    var body: some View {
        NavigationSplitView {
            SidebarView(
                jobs: filteredJobs,
                jobsListFilterRaw: $selectedFilterRaw,
                isFullListEmpty: sortedJobs.isEmpty,
                jobsSortOrderRaw: $jobsSortOrderRaw,
                selectedJob: $selectedJob,
                showingImportSheet: $showingImportSheet,
                showingCreateJobSheet: $showingCreateJobSheet,
                showingSettings: $showingSettings,
                onDelete: deleteJobs,
                jobsToDelete: $jobsToDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation
            )
        } detail: {
            if let selectedJob = selectedJob {
                JobDetailView(job: selectedJob)
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
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportJobsView()
        }
        .sheet(isPresented: $showingCreateJobSheet) {
            CreateJobView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
}

struct SidebarView: View {
    let jobs: [Job]
    @Binding var jobsListFilterRaw: String
    let isFullListEmpty: Bool
    @Binding var jobsSortOrderRaw: String
    @Binding var selectedJob: Job?
    @Binding var showingImportSheet: Bool
    @Binding var showingCreateJobSheet: Bool
    @Binding var showingSettings: Bool
    let onDelete: (IndexSet) -> Void
    @Binding var jobsToDelete: [Job]
    @Binding var showingDeleteConfirmation: Bool
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
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                }
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
