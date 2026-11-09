//
//  ProcedureStepsEditorView.swift
//  WindowReporter
//
//  Procedure steps for one testing type (embedded in TestingTypeDetailView).
//

import SwiftUI

struct ProcedureStepsEditorView: View {
    let testingTypeId: String
    let windowTypesLinkLabel: String
    @Binding var config: CachedProcedureConfig

    @State private var showingAddStep = false
    @State private var newStepLabel = ""
    @State private var newStepType = "text"
    @State private var newStepOptions = ""

    private let fieldTypes = ["text", "picker", "toggle", "measurement", "photoRequirement"]

    var body: some View {
        Group {
            Section("Procedure Steps") {
                ForEach($config.steps) { $step in
                    ProcedureStepRowView(step: $step, friendlyFieldType: friendlyFieldType)
                }
                .onDelete(perform: deleteSteps)
                .onMove(perform: moveSteps)
            }

            Section {
                Button {
                    showingAddStep = true
                } label: {
                    Label("Add Custom Step", systemImage: "plus")
                }
            }

            Section("Type list") {
                NavigationLink {
                    WindowTypesEditorView(
                        testingTypeId: testingTypeId,
                        testingTypeLabel: windowTypesLinkLabel
                    )
                } label: {
                    Label("\(windowTypesLinkLabel) types", systemImage: "square.grid.2x2")
                        .padding(.vertical, 2)
                }
            }
        }
        .sheet(isPresented: $showingAddStep) {
            addStepSheet
        }
    }

    private var addStepSheet: some View {
        NavigationStack {
            Form {
                TextField("Step Label", text: $newStepLabel)

                Picker("Field Type", selection: $newStepType) {
                    ForEach(fieldTypes, id: \.self) { t in
                        Text(friendlyFieldType(t)).tag(t)
                    }
                }

                if newStepType == "picker" {
                    TextField("Options (comma-separated)", text: $newStepOptions)
                }
            }
            .navigationTitle("New Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddStep = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let label = newStepLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !label.isEmpty else { return }
                        let id = label.lowercased().replacingOccurrences(of: " ", with: "_") + "_\(config.steps.count)"
                        let opts: [String]? = newStepType == "picker"
                            ? newStepOptions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            : nil
                        config.steps.append(CachedProcedureStep(
                            id: id, label: label, fieldType: newStepType,
                            options: opts, enabled: true, isBuiltIn: false
                        ))
                        newStepLabel = ""
                        newStepType = "text"
                        newStepOptions = ""
                        showingAddStep = false
                    }
                    .disabled(newStepLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func deleteSteps(at offsets: IndexSet) {
        var steps = config.steps
        let builtInIds = Set(steps.filter(\.isBuiltIn).map(\.id))
        let toRemove = offsets.filter { !builtInIds.contains(steps[$0].id) }
        steps.remove(atOffsets: IndexSet(toRemove))
        config = CachedProcedureConfig(steps: steps)
    }

    private func moveSteps(from: IndexSet, to: Int) {
        var steps = config.steps
        steps.move(fromOffsets: from, toOffset: to)
        config = CachedProcedureConfig(steps: steps)
    }

    private func friendlyFieldType(_ type: String) -> String {
        switch type {
        case "text": return "Text Field"
        case "picker": return "Picker"
        case "toggle": return "Yes/No Toggle"
        case "measurement": return "Measurement"
        case "photoRequirement": return "Photo Required"
        default: return type
        }
    }
}

private struct ProcedureStepRowView: View {
    @Binding var step: CachedProcedureStep
    let friendlyFieldType: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Label", text: $step.label)
                        .font(.body)
                        .disabled(!step.enabled)
                    Text(friendlyFieldType(step.fieldType))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 360, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 8)

                Menu {
                    if step.enabled {
                        Button("Make Inactive") { step.enabled = false }
                    } else {
                        Button("Make Active") { step.enabled = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
            }
            if step.fieldType == "picker", let opts = step.options, !opts.isEmpty {
                Text("Options: " + opts.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(step.enabled ? 1 : 0.5)
    }
}
