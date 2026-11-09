//
//  CustomizationsHubView.swift
//  WindowReporter
//
//  Hub for team customizations. Admin-only editing; shows team info and links
//  to each customization editor.
//

import AppKit
import SwiftUI

struct CustomizationsHubView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showingSignOutConfirmation = false
    @State private var isSyncing = false
    @State private var showingResetConfirmation = false
    @State private var syncStatusText: String?

    private var teamCode: String {
        supabase.organization?.teamCode ?? "------"
    }

    var body: some View {
        List {
            teamInfoSection
            syncSection
            if supabase.isAdmin {
                customizationLinksSection
                resetSection
            } else {
                memberSection
            }
            accountSection
        }
        .navigationTitle("Customizations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var teamInfoSection: some View {
        Section {
            HStack {
                Text("Team")
                Spacer()
                Text(supabase.organization?.name ?? "—")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            HStack {
                Text("Team Code")
                Spacer()
                Text(teamCode.uppercased())
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = teamCode
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(teamCode, forType: .string)
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
            HStack {
                Text("Role")
                Spacer()
                Text(supabase.isAdmin ? "Admin" : "Member")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Team Info")
        } footer: {
            Text("Share this team code with your team members so they can sync customizations.")
        }
    }

    private var customizationLinksSection: some View {
        Group {
            Section("Customize") {
                NavigationLink {
                    PhotoCategoriesEditorView()
                } label: {
                    Label("Photo Categories & Captions", systemImage: "photo.on.rectangle.angled")
                        .padding(.vertical, 3)
                }

                NavigationLink {
                    TestingTypesAndProceduresView()
                } label: {
                    Label("Testing Types and Procedures", systemImage: "list.clipboard")
                        .padding(.vertical, 3)
                }

                NavigationLink {
                    ReportBoilerplateEditorView()
                } label: {
                    Label("Report Boilerplate Text", systemImage: "doc.text")
                        .padding(.vertical, 3)
                }
            }
        }
    }

    private var memberSection: some View {
        Section {
            Text("Only team admins can edit customizations. Your app will automatically use your team's settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("Member Access")
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Button {
                    Task { await syncNow() }
                } label: {
                    HStack(spacing: 8) {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        if isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing)
                Spacer(minLength: 0)
            }

            if let syncStatusText {
                Text(syncStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let lastSync = TeamCustomizationCache.lastSyncDate() {
                Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset All to Defaults", role: .destructive) {
                showingResetConfirmation = true
            }
        } footer: {
            Text("Clears all team customizations and reverts to built-in defaults.")
        }
        .confirmationDialog("Reset all customizations to defaults?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset All", role: .destructive) {
                TeamCustomizationCache.clearAll()
                syncStatusText = "Reset to defaults."
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                showingSignOutConfirmation = true
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                Task { try? await supabase.signOut() }
            }
        }
    }

    private func syncNow() async {
        guard let orgId = supabase.organizationId else { return }
        isSyncing = true
        syncStatusText = "Syncing…"
        await CustomizationSyncService.syncAll(organizationId: orgId)
        syncStatusText = "Synced successfully."
        isSyncing = false
    }
}
