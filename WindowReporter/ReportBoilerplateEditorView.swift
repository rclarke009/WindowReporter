//
//  ReportBoilerplateEditorView.swift
//  WindowReporter
//

import AppKit
import SwiftUI

struct ReportBoilerplateEditorView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var fields: [String: String] = [:]
    @State private var isSaving = false
    @State private var statusMessage: String?

    static let fieldDefinitions: [(key: String, label: String, description: String)] = [
        ("test_performed", "Test Performed",
         "Describes the test method used (default: ASTM E1105 water test)."),
        ("background_info", "Background Information",
         "Cyclical wind pressure explanation and why hurricanes cause windows to fail."),
        ("recommendations", "Recommendations & Conclusion",
         "Summary of findings and recommended actions."),
        ("purpose", "Purpose",
         "Why the inspection was conducted and the date of loss."),
        ("observations", "Observations",
         "General observations statement included in the report."),
        ("engineering_letter_para1", "Engineering Letter - Paragraph 1",
         "First paragraph of the engineering letter (collaboration / professional opinion)."),
        ("engineering_letter_para2", "Engineering Letter - Paragraph 2",
         "Second paragraph (storm damage opinion and compliance)."),
        ("engineering_letter_para3", "Engineering Letter - Paragraph 3",
         "Third paragraph (closing / appreciation)."),
    ]

    var body: some View {
        List {
            ForEach(Self.fieldDefinitions, id: \.key) { def in
                NavigationLink {
                    BoilerplateFieldEditor(
                        fieldKey: def.key,
                        label: def.label,
                        description: def.description,
                        text: binding(for: def.key),
                        onSave: { text in await saveField(def.key, content: text) }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(def.label)
                        let preview = fields[def.key] ?? ""
                        if !preview.isEmpty {
                            Text(preview.prefix(80) + (preview.count > 80 ? "…" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("using default")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Report Text")
        .task { await load() }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fields[key] ?? "" },
            set: { fields[key] = $0 }
        )
    }

    private func load() async {
        guard let orgId = supabase.organizationId else { return }
        await CustomizationSyncService.syncReportBoilerplate(organizationId: orgId)
        if let cached = TeamCustomizationCache.reportBoilerplate() {
            fields = cached
        }
    }

    private func saveField(_ key: String, content: String) async {
        guard let orgId = supabase.organizationId else { return }
        isSaving = true
        do {
            try await CustomizationSyncService.upsertReportBoilerplate(
                organizationId: orgId, fieldKey: key, content: content
            )
            fields[key] = content
            TeamCustomizationCache.saveReportBoilerplate(fields)
            statusMessage = "Saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            print("MYDEBUG →", "saveBoilerplate error: \(error)")
        }
        isSaving = false
    }
}

private struct BoilerplateFieldEditor: View {
    let fieldKey: String
    let label: String
    let description: String
    @Binding var text: String
    let onSave: (String) async -> Void

    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Content") {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            Section {
                Button {
                    Task {
                        isSaving = true
                        await onSave(text)
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)

                if !text.isEmpty {
                    Button("Clear (use default)", role: .destructive) {
                        text = ""
                    }
                }
            }
        }
        .navigationTitle(label)
    }
}
