//
//  AuthGateView.swift
//  WindowReporter
//
//  Authentication gate for team customizations (macOS).
//

import SwiftUI

struct AuthGateView<Content: View>: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if supabase.isAuthenticated {
                if supabase.organizationId != nil {
                    content()
                } else {
                    OrgSetupView()
                }
            } else {
                AuthFormView()
            }
        }
    }
}

// MARK: - Auth Form (Sign In / Sign Up)

private struct AuthFormView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(isSignUp ? "Create Admin Account" : "Sign In")
                .font(.title2.bold())

            Text("Sign in to manage your team's customizations in ReportWriter. Field staff sync the same team settings in the WTestBeta app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                if isSignUp {
                    TextField("Your Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isSignUp ? .newPassword : .password)
            }
            .frame(maxWidth: 320)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit() }
            } label: {
                if isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty))
            .frame(maxWidth: 320)

            Button(isSignUp ? "Already have an account? Sign In" : "Need an account? Sign Up") {
                withAnimation { isSignUp.toggle() }
                errorMessage = nil
            }
            .font(.footnote)

            Spacer()
        }
        .padding()
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        do {
            if isSignUp {
                try await supabase.signUp(email: email, password: password, displayName: displayName)
            } else {
                try await supabase.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = userFacingErrorMessage(error)
            print("MYDEBUG →", "Auth error: \(error)")
        }
        isWorking = false
    }
}

// MARK: - User-facing error text

/// Maps common URL/network errors to guidance. Unwraps nested URLErrors (Supabase often wraps them).
private func userFacingErrorMessage(_ error: Error) -> String {
    if let urlError = firstURLError(in: error) {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
            return "No internet connection. Check your network and try again."
        case .cannotFindHost, .dnsLookupFailed:
            if let host = failingURLHost(from: error) {
                return "This Mac could not resolve \(host) in DNS (error -1003). The URL in Config is often still correct. Try: disable VPN, switch network, or toggle Wi-Fi; after sleep, wait or reboot. If it persists, re-copy **Project URL** from Supabase (Settings → API) into Config.plist as SupabaseURL."
            }
            return "Could not resolve the Supabase host. Check VPN, DNS, and that SupabaseURL matches your Project URL in Supabase (Settings → API)."
        case .cannotConnectToHost, .timedOut:
            return "Could not connect to the Supabase server. Check the network or VPN, or that SupabaseURL in Config.plist matches Settings → API."
        case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected:
            return "Secure connection to Supabase failed. Check for proxies or TLS interceptors, and that your system time is correct. Verify SupabaseURL uses https."
        case .cancelled:
            return "The request was cancelled. Try again."
        default:
            return urlError.localizedDescription
        }
    }
    return error.localizedDescription
}

/// Walks NSUnderlyingError / NSError chains to find a URLError (auth libraries often wrap these).
private func firstURLError(in error: Error) -> URLError? {
    var err: Error? = error
    for _ in 0..<10 {
        guard let e = err else { break }
        if let u = e as? URLError { return u }
        err = (e as NSError).userInfo[NSUnderlyingErrorKey] as? Error
    }
    return nil
}

/// Host from `NSURLErrorFailingURLStringKey` in the error chain (what actually failed, e.g. `xyz.supabase.co`).
private func failingURLHost(from error: Error) -> String? {
    var err: Error? = error
    for _ in 0..<10 {
        guard let e = err else { break }
        let ns = e as NSError
        let key = NSURLErrorFailingURLStringErrorKey
        if let urlString = (ns.userInfo[key] as? String) ?? (ns.userInfo["NSErrorFailingURLStringKey"] as? String),
           let u = URL(string: urlString), let host = u.host, !host.isEmpty {
            return host
        }
        if let u = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL, let host = u.host, !host.isEmpty {
            return host
        }
        err = ns.userInfo[NSUnderlyingErrorKey] as? Error
    }
    return nil
}

// MARK: - Org Setup (create or join)

private struct OrgSetupView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var mode: OrgSetupMode = .choose
    @State private var orgName = ""
    @State private var teamCode = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    enum OrgSetupMode {
        case choose, create, join
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "building.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            switch mode {
            case .choose:
                chooseView
            case .create:
                createView
            case .join:
                joinView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Sign Out") {
                Task { try? await supabase.signOut() }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var chooseView: some View {
        VStack(spacing: 16) {
            Text("Set Up Your Team")
                .font(.title2.bold())

            Text("Create a new team or join an existing one with a team code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation { mode = .create }
            } label: {
                Label("Create New Team", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 320)

            Button {
                withAnimation { mode = .join }
            } label: {
                Label("Join Existing Team", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: 320)
        }
    }

    private var createView: some View {
        VStack(spacing: 16) {
            Text("Create Your Team")
                .font(.title2.bold())

            Text("You'll be the admin. Team members can join using the code you'll get.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Team / Company Name", text: $orgName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            Button {
                Task { await createOrg() }
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Create Team").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || orgName.isEmpty)
            .frame(maxWidth: 320)

            Button("Back") { withAnimation { mode = .choose } }
                .font(.footnote)
        }
    }

    private var joinView: some View {
        VStack(spacing: 16) {
            Text("Join a Team")
                .font(.title2.bold())

            Text("Enter the 6-character team code from your admin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Team Code", text: $teamCode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
                .font(.title3.monospaced())

            Button {
                Task { await joinTeam() }
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Join Team").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || teamCode.count < 4)
            .frame(maxWidth: 320)

            Button("Back") { withAnimation { mode = .choose } }
                .font(.footnote)
        }
    }

    private func createOrg() async {
        isWorking = true
        errorMessage = nil
        do {
            let org = try await supabase.createOrganization(name: orgName)
            print("MYDEBUG →", "Created org: \(org.name) code: \(org.teamCode)")
        } catch {
            errorMessage = userFacingErrorMessage(error)
            print("MYDEBUG →", "Create org error: \(error)")
        }
        isWorking = false
    }

    private func joinTeam() async {
        isWorking = true
        errorMessage = nil
        do {
            try await supabase.joinTeam(code: teamCode)
        } catch {
            errorMessage = userFacingErrorMessage(error)
            print("MYDEBUG →", "Join team error: \(error)")
        }
        isWorking = false
    }
}
