//
//  ContentView.swift
//  AuthTest
//
//  Created by Magesh K on 20/07/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import AltSign
import AnisetteKit

struct ContentView: View {
    @State private var appleID = ""
    @State private var password = ""
    @State private var statusMessage = "Enter credentials to start"
    @State private var isAuthenticating = false
    @State private var showOTPInput = false
    @State private var otpCode = ""
    @State private var pendingOTPHandler: ((String?) -> Void)? = nil
    @State private var enableVerboseLogging = false
    @State private var useUnicornEmulation = true

    
    @AppStorage("packageDownloadURL") private var packageDownloadURL: String = ""
    @State private var isLibrariesReady = false
    @State private var isDownloadingLibraries = false
    @State private var showFileImporter = false
    @State private var isBannerDismissed = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if !isLibrariesReady || !isBannerDismissed {
                    VStack(spacing: 12) {
                        ZStack(alignment: .trailing) {
                            Text("Setup Required: ADI Libraries")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            if isLibrariesReady {
                                Button(action: {
                                    withAnimation {
                                        isBannerDismissed = true
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .help("Dismiss banner for this session")
                            }
                        }

                        Text("Please import the 2 required ADI native shared libraries:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(alignment: .leading, spacing: 6) {
                            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                            let hasSSC = FileManager.default.fileExists(atPath: cachesURL.appendingPathComponent("libstoreservicescore.so").path)
                            let hasCoreADI = FileManager.default.fileExists(atPath: cachesURL.appendingPathComponent("libCoreADI.so").path)

                            HStack {
                                Image(systemName: hasSSC ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor(hasSSC ? .green : .red)
                                Text("libstoreservicescore.so")
                                    .font(.system(.caption, design: .monospaced))
                            }

                            HStack {
                                Image(systemName: hasCoreADI ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor(hasCoreADI ? .green : .red)
                                Text("libCoreADI.so")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 4)

                        if !isLibrariesReady {
                            Button(action: { showFileImporter = true }) {
                                Label("Import .so Libraries", systemImage: "square.and.arrow.down")
                                    .font(.body.weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            HStack(spacing: 12) {
                                Button(action: { showFileImporter = true }) {
                                    Label("Import .so Libraries", systemImage: "square.and.arrow.down")
                                        .font(.body.weight(.bold))
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    withAnimation {
                                        isBannerDismissed = true
                                    }
                                }) {
                                    Text("Dismiss")
                                        .bold()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        /*
                        // Package Downloader & Importer (Disabled for now)
                        TextField("https://.../apple-music.apk", text: $packageDownloadURL)
                            #if os(tvOS)
                            .textFieldStyle(DefaultTextFieldStyle())
                            #else
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            #endif
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled(true)
                            .disabled(isDownloadingLibraries)

                        Button(action: downloadAndPrepareLibraries) {
                            Text("Download & Prepare Libraries")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloadingLibraries || packageDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        */
                    }
                    .padding()
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                VStack(spacing: 12) {
                    TextField("Email ID", text: $appleID)
                        #if os(tvOS)
                        .textFieldStyle(DefaultTextFieldStyle())
                        #else
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #endif
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                        .autocorrectionDisabled(true)
                        #if os(iOS) || os(visionOS)
                        .keyboardType(.emailAddress)
                        #endif
                        .disabled(isAuthenticating || !isLibrariesReady)
                    
                    SecureField("Password", text: $password)
                        #if os(tvOS)
                        .textFieldStyle(DefaultTextFieldStyle())
                        #else
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #endif
                        #if !os(macOS)
                        .textContentType(.password)
                        #endif
                        .disabled(isAuthenticating || !isLibrariesReady)
                    
                    Toggle("Verbose AltSign Logging", isOn: $enableVerboseLogging)
                        .onChange(of: enableVerboseLogging) { newValue in
                            AltSign.setLogging(newValue)
                        }
                    
                    Toggle("Use Unicorn Emulation (UC)", isOn: $useUnicornEmulation)

                }
                .padding(.horizontal)
                
                if showOTPInput {
                    VStack(spacing: 12) {
                        Text("2-Factor Authentication Code Required")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        TextField("6-Digit Code", text: $otpCode)
                            #if os(tvOS)
                            .textFieldStyle(DefaultTextFieldStyle())
                            #else
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            #endif
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            .textContentType(.oneTimeCode)
                            #endif
                            .autocorrectionDisabled(true)
                            #if os(iOS) || os(visionOS)
                            .keyboardType(.numberPad)
                            #endif
                            .disabled(isAuthenticating)
                        
                        Button("Submit Code") {
                            submitOTP()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAuthenticating || otpCode.count < 6)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                Button(action: startAuthentication) {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Log In")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .disabled(isAuthenticating || !isLibrariesReady || appleID.isEmpty || password.isEmpty)
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                if isLibrariesReady {
                    Button(role: .destructive, action: clearImportedLibraries) {
                        Label("Clear Loaded Libraries", systemImage: "trash")
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                NavigationLink(destination: LicensesView()) {
                    Label("Open Source Licenses", systemImage: "doc.text")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

            }
            .navigationTitle("AuthTest")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: clearImportedLibraries) {
                        Image(systemName: "trash")
                    }
                    .help("Clear Loaded Libraries")
                }
            }
            .onAppear {
                checkLibrariesReady()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item, .data, UTType(filenameExtension: "so") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                handleImportedSOFiles(result)
            }
        }
    }

    func clearImportedLibraries() {
        isBannerDismissed = false
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fm = FileManager.default
        try? fm.removeItem(at: cachesURL.appendingPathComponent("libstoreservicescore.so"))
        try? fm.removeItem(at: cachesURL.appendingPathComponent("libCoreADI.so"))
        checkLibrariesReady()
        statusMessage = "Loaded libraries cleared. Please import 64-bit ARM64 .so files."
    }

    func isValid64BitELF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 6)
        guard header.count >= 5 else { return false }
        // 0x7F 'E' 'L' 'F', byte 4: 2 = 64-bit (ELFCLASS64)
        return header[0] == 0x7F && header[1] == 0x45 && header[2] == 0x4C && header[3] == 0x46 && header[4] == 2
    }

    func handleImportedSOFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let fm = FileManager.default

            var importedCount = 0
            var invalidArchCount = 0

            for url in urls {
                let hasSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let filename = url.lastPathComponent.lowercased()
                let targetName: String?
                if filename.contains("storeservices") {
                    targetName = "libstoreservicescore.so"
                } else if filename.contains("coreadi") {
                    targetName = "libCoreADI.so"
                } else {
                    targetName = nil
                }

                guard let target = targetName else {
                    print("[AuthTest] Ignored file: \(url.lastPathComponent) (expected libstoreservicescore.so or libCoreADI.so)")
                    continue
                }

                guard isValid64BitELF(at: url) else {
                    print("[AuthTest] ERROR: \(url.lastPathComponent) is not a 64-bit ELF file!")
                    invalidArchCount += 1
                    statusMessage = "\(url.lastPathComponent) is not a valid 64-bit ARM64 ELF file."
                    continue
                }

                let destURL = cachesURL.appendingPathComponent(target)
                do {
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: url, to: destURL)
                    importedCount += 1
                    print("[AuthTest] Successfully imported \(target) -> \(destURL.path)")
                } catch {
                    print("[AuthTest] Failed to copy \(target): \(error.localizedDescription)")
                }
            }

            if importedCount > 0 {
                checkLibrariesReady()
            } else if invalidArchCount == 0 {
                statusMessage = "Please select 'libstoreservicescore.so' or 'libCoreADI.so'."
            }

        case .failure(let error):
            statusMessage = "File selection error: \(error.localizedDescription)"
        }
    }

    func checkLibrariesReady() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fm = FileManager.default
        let hasSSC = fm.fileExists(atPath: cachesURL.appendingPathComponent("libstoreservicescore.so").path)
        let hasCoreADI = fm.fileExists(atPath: cachesURL.appendingPathComponent("libCoreADI.so").path)

        if hasSSC && hasCoreADI && LocalAnisetteProvider.validateLibrariesExist(at: cachesURL) {
            isLibrariesReady = true
            statusMessage = "All ADI libraries ready. Enter credentials to log in."
        } else {
            isLibrariesReady = false
            if !hasSSC && !hasCoreADI {
                statusMessage = "Please import libstoreservicescore.so and libCoreADI.so."
            } else if !hasSSC {
                statusMessage = "Imported libCoreADI.so. Still need libstoreservicescore.so."
            } else {
                statusMessage = "Imported libstoreservicescore.so. Still need libCoreADI.so."
            }
        }
    }

    func downloadAndPrepareLibraries() {
        let trimmed = packageDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            statusMessage = "Invalid package download URL."
            return
        }

        isDownloadingLibraries = true
        statusMessage = "Starting download..."

        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

        Task {
            do {
                try await APKExtractor.extractLibraries(from: url, to: cachesURL) { msg in
                    Task { @MainActor in
                        statusMessage = msg
                    }
                }
                await MainActor.run {
                    isDownloadingLibraries = false
                    checkLibrariesReady()
                }
            } catch {
                await MainActor.run {
                    isDownloadingLibraries = false
                    statusMessage = "Setup error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startAuthentication() {
        isAuthenticating = true
        showOTPInput = false
        statusMessage = "Retrieving anisette headers (Unicorn emulator)..."
        
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        
        Task {
            await runAuthSequence(provisioningDir: cachesURL)
        }
    }
    
    func runAuthSequence(provisioningDir: URL) async {
        let identifier = UUID()
        
        do {
            if !LocalAnisetteProvider.validateLibrariesExist(at: provisioningDir) {
                let trimmed = packageDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed), !trimmed.isEmpty else {
                    throw LocalAnisetteError.librariesNotFound(
                        reason: "Required ADI libraries missing. Please provide a valid Package Download URL to extract them automatically."
                    )
                }
                await MainActor.run { statusMessage = "Downloading package & extracting libraries..." }
                try await APKExtractor.extractLibraries(from: url, to: provisioningDir) { msg in
                    Task { @MainActor in statusMessage = msg }
                }
            }

            let provider = try LocalAnisetteProvider(provisioningDir: provisioningDir) {
                provisioningDir
            }
            let headers: [String: String]
            if useUnicornEmulation {
                print("[AuthTest] Retrieving anisette headers via Unicorn Emulation (getHeadersUC)...")
                headers = try await provider.getHeadersUC(identifier: identifier)
            } else {
                print("[AuthTest] Retrieving anisette headers via Native loader (getHeaders)...")
                headers = try await provider.getHeaders(identifier: identifier)
            }

            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let dateString = formatter.string(from: Date())

            let formattedJSON: [String: String] = [
                "deviceSerialNumber": "0",
                "machineID": headers["X-Apple-I-MD-M"] ?? "",
                "oneTimePassword": headers["X-Apple-I-MD"] ?? "",
                "routingInfo": headers["X-Apple-I-MD-RINFO"] ?? "17106176",
                "deviceDescription": provider.clientInfo,
                "localUserID": headers["X-Apple-I-MD-LU"] ?? "0000000000000000000000000000000000000000000000000000000000000001",
                "deviceUniqueIdentifier": identifier.uuidString.uppercased(),
                "date": dateString,
                "locale": Locale.current.identifier.components(separatedBy: "@").first ?? "en_US",
                "timeZone": TimeZone.current.abbreviation() ?? "UTC"
            ]
            
            guard let anisetteData = ALTAnisetteData(json: formattedJSON) else {
                await MainActor.run {
                    self.statusMessage = "Error: Failed to instantiate ALTAnisetteData"
                    self.isAuthenticating = false
                }
                return
            }
            
            await MainActor.run {
                self.statusMessage = "Authenticating with Apple..."
            }
            
            ALTAppleAPI.shared.authenticate(
                appleID: self.appleID,
                password: self.password,
                anisetteData: anisetteData,
                verificationHandler: { completion in
                    Task { @MainActor in
                        self.isAuthenticating = false
                        self.showOTPInput = true
                        self.statusMessage = "Sent verification code to your Apple devices."
                        self.pendingOTPHandler = completion
                    }
                },
                completionHandler: { account, session, error in
                    Task { @MainActor in
                        self.isAuthenticating = false
                        if let error = error {
                            let detailedMessage = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
                            self.statusMessage = "Authentication failed: \(detailedMessage)"
                            print("[AuthTest] Authentication failed: \(detailedMessage) | Details: \(error)")
                        } else if let account = account {
                            self.statusMessage = "Authentication Succeeded!\nAccount: \(account.appleID)\nSession token obtained."
                            print("[AuthTest] Authentication Succeeded! Account: \(account.appleID)")
                        }
                    }
                }
            )
            
        } catch {
            await MainActor.run {
                self.statusMessage = "Anisette generation failed: \(error.localizedDescription)"
                print("[AuthTest] Anisette generation failed: \(error.localizedDescription)")
                self.isAuthenticating = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                exit(1)
            }
        }
    }

    
    func submitOTP() {
        guard let handler = pendingOTPHandler else { return }
        isAuthenticating = true
        statusMessage = "Submitting verification code..."
        
        let code = otpCode
        self.otpCode = ""
        self.showOTPInput = false
        self.pendingOTPHandler = nil
        
        handler(code)
    }
}
