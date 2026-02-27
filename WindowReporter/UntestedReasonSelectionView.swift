//
//  UntestedReasonSelectionView.swift
//  WindowReporter
//
//  macOS – select reason for "Not Tested" (same options as iOS app)
//

import SwiftUI
import AppKit

struct UntestedReasonSelectionView: View {
    @Binding var selectedReason: String
    @Binding var customReason: String
    let onDismiss: () -> Void
    
    private let predefinedReasons: [String] = [
        "Inaccessible",
        "Damaged so that it would not close properly.",
        "Windows with air conditioning units installed cannot be tested, as the presence of the unit prevents proper sealing of the window assembly. This compromises the integrity of the test conditions, rendering the results invalid.",
        "Window was blocked by items that were not movable.",
        "Did not have access to window because of locked door."
    ]
    
    @State private var showingCustomInput = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        // Predefined reasons
                        ForEach(predefinedReasons, id: \.self) { reason in
                            Button(action: {
                                selectedReason = reason
                                showingCustomInput = false
                                customReason = ""
                            }) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reason)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    if selectedReason == reason {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title3)
                                    }
                                }
                                .padding()
                                .background(selectedReason == reason && customReason.isEmpty ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Custom/Other option
                        Button(action: {
                            selectedReason = "Other/Custom"
                            showingCustomInput = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Other/Custom")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if selectedReason == "Other/Custom" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                            .padding()
                            .background(selectedReason == "Other/Custom" ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Custom text input (shown when Other/Custom is selected)
                        if showingCustomInput || selectedReason == "Other/Custom" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Enter custom reason:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Enter custom reason", text: $customReason, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            }
                            .padding()
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("Done")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(selectedReason == "Other/Custom" && customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("Cancel")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
            .navigationTitle("Select Reason")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .disabled(selectedReason == "Other/Custom" && customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 440, height: 520)
        .onAppear {
            if selectedReason == "Other/Custom" {
                showingCustomInput = true
            }
        }
    }
}
