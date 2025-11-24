//
//  ImportJobsView.swift
//  WindowReporter
//
//  macOS import view
//

import SwiftUI
import UniformTypeIdentifiers

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
                if !importService.isImporting && importService.importError == nil {
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

