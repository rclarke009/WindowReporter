//
//  TestingHubView.swift
//  WindowReporter
//
//  Lists enabled testing types for the job (parity with field app Testing tab).
//

import SwiftUI
import CoreData

struct TestingHubView: View {
    @ObservedObject var job: Job
    @Environment(\.managedObjectContext) private var viewContext
    @State private var destination: TestingDestination?

    private var enabledTypeIds: [String] {
        TestingTypesHelper.enabledTypeIds(from: job)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Testing")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Text("Complete each type of testing requested for this job.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 12)

            List {
                ForEach(enabledTypeIds, id: \.self) { typeId in
                    Button {
                        if TestingTypesHelper.isWindows(typeId) {
                            destination = .windows
                        } else {
                            destination = .sections(typeId: typeId)
                        }
                    } label: {
                        TestingTypeRow(job: job, typeId: typeId)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(item: $destination) { destination in
            NavigationStack {
                switch destination {
                case .windows:
                    WindowsListView(job: job)
                case .sections(let typeId):
                    ReporterTypeSectionsListView(job: job, testingTypeId: typeId)
                }
            }
            .frame(minWidth: 520, minHeight: 480)
        }
    }
}

private enum TestingDestination: Identifiable {
    case windows
    case sections(typeId: String)

    var id: String {
        switch self {
        case .windows:
            return "windows"
        case .sections(let typeId):
            return "sections-\(typeId)"
        }
    }
}

private struct TestingTypeRow: View {
    @ObservedObject var job: Job
    let typeId: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: imageNameForType(typeId))
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
            Text(TestingTypesHelper.displayName(for: typeId, job: job))
                .font(.body)
        }
        .padding(.vertical, 4)
    }

    private func imageNameForType(_ typeId: String) -> String {
        switch typeId {
        case "windows": return "square.grid.3x3"
        case "roof": return "house.fill"
        case "attic": return "arrow.up.to.line"
        case "floors": return "square.split.2x2"
        case "walls": return "rectangle.portrait"
        case "structural": return "hammer.fill"
        case "electrical": return "bolt.fill"
        case "moldMoisture": return "drop.fill"
        case "siding": return "square.stack.3d.up"
        case "doors": return "door.garage.closed"
        default: return "checklist"
        }
    }
}
