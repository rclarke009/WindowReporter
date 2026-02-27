//
//  WindowTypePicker.swift
//  WindowReporter
//
//  macOS image-based window type picker (matches iOS app types and images).
//

import SwiftUI
import AppKit

// MARK: - Window Type Enum (macOS)
// Same raw values as iOS for data consistency. Ordered from most common to least common.
enum ReporterWindowType: String, CaseIterable, Identifiable {
    case singleHung = "Single Hung"
    case sliding = "Sliding"
    case casement = "Casement"
    case fixed = "Fixed"
    case doubleHung = "Double Hung"
    case awning = "Awning"
    case centerPivot = "Center Pivot"
    case hopper = "Hopper"
    case jalousie = "Jalousie"
    
    var id: String { rawValue }
    
    var imageName: String {
        switch self {
        case .awning: return "window-awning"
        case .casement: return "window-casement"
        case .centerPivot: return "window-center-pivot"
        case .doubleHung: return "window-doublehung"
        case .fixed: return "window-fixed"
        case .hopper: return "window-hopper"
        case .jalousie: return "window-jalousie"
        case .singleHung: return "window-singlehung"
        case .sliding: return "window-sliding"
        }
    }
    
    /// Load from window-types folder in bundle (macOS).
    var image: NSImage? {
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "window-types"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let img = NSImage(named: "window-types/\(imageName)") {
            return img
        }
        if let img = NSImage(named: imageName) {
            return img
        }
        return nil
    }
}

// MARK: - Window Type Picker Button (triggers sheet)
struct ReporterWindowTypePickerView: View {
    @Binding var selectedWindowType: String
    @State private var showingPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { showingPicker = true }) {
                HStack {
                    Image(systemName: selectedWindowType.isEmpty ? "square" : "checkmark.square.fill")
                        .foregroundColor(selectedWindowType.isEmpty ? .secondary : .accentColor)
                        .font(.system(size: 20))
                    Text(selectedWindowType.isEmpty ? "Select Window Type" : selectedWindowType)
                        .foregroundColor(selectedWindowType.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingPicker) {
            ReporterWindowTypeSelectionView(selectedWindowType: $selectedWindowType)
                .frame(minWidth: 520, minHeight: 480)
        }
    }
}

// MARK: - Window Type Selection Grid (sheet)
struct ReporterWindowTypeSelectionView: View {
    @Binding var selectedWindowType: String
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select Window Type")
                .font(.headline)
                .padding()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(ReporterWindowType.allCases) { windowType in
                        Button(action: {
                            selectedWindowType = windowType.rawValue
                            dismiss()
                        }) {
                            VStack(spacing: 8) {
                                if let nsImage = windowType.image {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 100, height: 100)
                                } else {
                                    Image(systemName: "square.grid.3x3")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, height: 100)
                                }
                                Text(windowType.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedWindowType == windowType.rawValue ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedWindowType == windowType.rawValue ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
    }
}
