//
//  ImportJobsView.swift
//  WindowReporter
//
//  macOS import view
//

import SwiftUI
import UniformTypeIdentifiers

private struct DuplicateResolutionSheetItem: Identifiable {
    let id = UUID()
    let addressSummary: String
}

private struct DuplicateResolutionSheet: View {
    let addressSummary: String
    let onReplace: () -> Void
    let onSkip: () -> Void
    let onImportAsNew: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Job Already Exists")
                .font(.title2)
                .fontWeight(.semibold)
            Text("A job with this address is already in the app. Choose how to proceed.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(addressSummary)
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(spacing: 12) {
                Button("Replace existing job") {
                    onReplace()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("Import as new job") {
                    onImportAsNew()
                }
                .frame(maxWidth: .infinity)
                Button("Skip") {
                    onSkip()
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 400)
    }
}

struct ImportJobsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importService = JobImportService(context: PersistenceController.shared.container.viewContext)
    @State private var showingDocumentPicker = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Import Job Package")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Select a ZIP file or folder containing job data to import into the app")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Show detected package type if available
                    if let packageType = importService.detectedPackageType {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: packageType.icon)
                                    .foregroundColor(packageType == .fullJob ? .orange : .blue)
                                Text("Detected: \(packageType.rawValue)")
                                    .font(.headline)
                            }
                            Text(packageType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 40)
                    }
                    
                    // Import Options
                    VStack(spacing: 16) {
                        Button(action: {
                            showingDocumentPicker = true
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Choose ZIP File or Folder")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(importService.isImporting)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    if importService.isImporting {
                        VStack(spacing: 12) {
                            ProgressView(value: importService.importProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            if let packageType = importService.detectedPackageType {
                                Text("Importing \(packageType.rawValue)...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("\(Int(importService.importProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    if let error = importService.importError {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Import Jobs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: Binding<DuplicateResolutionSheetItem?>(
            get: {
                guard let pending = importService.pendingDuplicateResolution else { return nil }
                let j = pending.package.job
                let parts = [j.addressLine1, j.city, j.state, j.zip].compactMap { $0 }
                let summary = parts.isEmpty ? "Same job (by ID)" : parts.joined(separator: ", ")
                return DuplicateResolutionSheetItem(addressSummary: summary)
            },
            set: { _, _ in }
        )) { (item: DuplicateResolutionSheetItem) in
            DuplicateResolutionSheet(
                addressSummary: item.addressSummary,
                onReplace: {
                    Task {
                        await importService.resolveDuplicate(choice: .replace)
                        if importService.importError == nil {
                            await MainActor.run { dismiss() }
                        }
                    }
                },
                onSkip: {
                    Task {
                        await importService.resolveDuplicate(choice: .skip)
                    }
                },
                onImportAsNew: {
                    Task {
                        await importService.resolveDuplicate(choice: .importAsNew)
                        if importService.importError == nil {
                            await MainActor.run { dismiss() }
                        }
                    }
                }
            )
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.zip, .folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importService.importJobPackage(from: url)
                if !importService.isImporting && importService.importError == nil && importService.pendingDuplicateResolution == nil {
                    await MainActor.run {
                        dismiss()
                    }
                }
            }
        case .failure(let error):
            importService.importError = error.localizedDescription
        }
    }
}

#Preview {
    ImportJobsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

