//
//  APKExtractor.swift
//  AuthTest
//
//  Created by Magesh K on 17/08/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import Foundation
import Compression

public struct APKPackageInfo: Codable {
    public let apkmVersion: Int?
    public let apkTitle: String?
    public let appName: String?
    public let releaseVersion: String?
    public let variant: String?
    public let releaseTitle: String?
    public let versioncode: String?
    public let pname: String?
    public let postDate: String?
    public let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case apkmVersion = "apkm_version"
        case apkTitle = "apk_title"
        case appName = "app_name"
        case releaseVersion = "release_version"
        case variant
        case releaseTitle = "release_title"
        case versioncode
        case pname
        case postDate = "post_date"
        case capabilities
    }
}

public enum APKExtractorError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case invalidZIP(String)
    case invalidPackageInfo(String)
    case extractionFailed(String)
    case missingLibraries([String])

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid package download URL."
        case .downloadFailed(let msg):
            return "Failed to download package: \(msg)"
        case .invalidZIP(let msg):
            return "Invalid APK/APKM archive: \(msg)"
        case .invalidPackageInfo(let msg):
            return "Package validation failed: \(msg)"
        case .extractionFailed(let msg):
            return "Failed to decompress ADI component: \(msg)"
        case .missingLibraries(let names):
            return "Could not find required ADI libraries (\(names.joined(separator: ", "))) in package."
        }
    }
}

public struct APKExtractor {
    public static let expectedPackageName = "com.apple.android.music"
    public static let expectedReleaseVersion = "6.5.0"
    public static let expectedVersionCode = "1580"
    public static let expectedAppName = "Apple Music"

    public static let targetLibraries = [
        "libstoreservicescore.so",
        "libCoreADI.so"
    ]

    public static func extractLibraries(
        from packageURL: URL,
        to destinationDir: URL,
        progress: ((String) -> Void)? = nil
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let localFile: URL
        let isRemote = packageURL.scheme == "http" || packageURL.scheme == "https"

        if isRemote {
            progress?("Downloading package...")
            let (tempDownloadURL, response) = try await URLSession.shared.download(from: packageURL)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                throw APKExtractorError.downloadFailed("Server returned non-200 HTTP response.")
            }
            localFile = tempDownloadURL
        } else {
            localFile = packageURL
        }
        defer {
            if isRemote {
                try? fileManager.removeItem(at: localFile)
            }
        }

        progress?("Inspecting archive...")
        let fileHandle = try FileHandle(forReadingFrom: localFile)
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        print("[APKExtractor] Opening package: \(localFile.lastPathComponent) (\(fileSize) bytes)")

        try extractFromArchive(handle: fileHandle, destinationDir: destinationDir, progress: progress)
        print("[APKExtractor] Extraction completed successfully.")
        progress?("Libraries extracted & verified.")
    }

    private static func extractFromArchive(
        handle: FileHandle,
        destinationDir: URL,
        progress: ((String) -> Void)?
    ) throws {
        let entries = try parseZIPEntries(handle: handle)
        print("[APKExtractor] Parsed \(entries.count) entries in archive.")

        for (i, entry) in entries.enumerated() {
            print("[APKExtractor] [\(i + 1)/\(entries.count)] \(entry.fileName) (size: \(entry.uncompressedSize), method: \(entry.compressionMethod))")
        }

        // 1. Validate info.json if present
        if let infoEntry = entries.first(where: { $0.fileName.lowercased().hasSuffix("info.json") }) {
            print("[APKExtractor] Found info.json at entry: \(infoEntry.fileName)")
            progress?("Validating package info.json...")
            if let infoData = try? decompressEntry(handle: handle, entry: infoEntry) {
                let decoder = JSONDecoder()
                if let info = try? decoder.decode(APKPackageInfo.self, from: infoData) {
                    print("[APKExtractor] info.json contents: pname=\(info.pname ?? "nil"), release=\(info.releaseVersion ?? "nil"), code=\(info.versioncode ?? "nil"), app=\(info.appName ?? "nil")")
                    if let pname = info.pname, !pname.isEmpty, pname != expectedPackageName {
                        print("[APKExtractor] ERROR: Package name mismatch! Got \(pname), expected \(expectedPackageName)")
                        throw APKExtractorError.invalidPackageInfo("Unexpected package name '\(pname)', expected '\(expectedPackageName)'.")
                    }
                    if let ver = info.releaseVersion, !ver.isEmpty, let code = info.versioncode, !code.isEmpty {
                        if ver != expectedReleaseVersion && code != expectedVersionCode {
                            print("[APKExtractor] ERROR: Version mismatch! Got \(ver) (\(code)), expected \(expectedReleaseVersion) (\(expectedVersionCode))")
                            throw APKExtractorError.invalidPackageInfo("Version mismatch: Found '\(ver)' (\(code)), expected '\(expectedReleaseVersion)' (\(expectedVersionCode)).")
                        }
                    }
                } else {
                    print("[APKExtractor] WARNING: Failed to decode info.json as APKPackageInfo")
                }
            }
        }

        // 2. Search root archive
        var foundLibraries = try extractTargetLibraries(entries: entries, handle: handle, destinationDir: destinationDir, progress: progress)
        print("[APKExtractor] Direct extraction found: \(foundLibraries)")

        // 3. If libraries not found in root, inspect all nested .apk/.zip files
        if foundLibraries.count < targetLibraries.count {
            let nestedApkEntries = entries.filter {
                let lower = $0.fileName.lowercased()
                return lower.hasSuffix(".apk") || lower.hasSuffix(".zip")
            }.sorted { a, b in
                let aArm = a.fileName.lowercased().contains("arm64")
                let bArm = b.fileName.lowercased().contains("arm64")
                if aArm != bArm { return aArm }
                let aBase = a.fileName.lowercased().contains("base")
                let bBase = b.fileName.lowercased().contains("base")
                return aBase && !bBase
            }

            print("[APKExtractor] Found \(nestedApkEntries.count) nested split APKs/ZIPs to inspect: \(nestedApkEntries.map { $0.fileName })")

            for apkEntry in nestedApkEntries {
                print("[APKExtractor] Decompressing nested package: \(apkEntry.fileName)...")
                progress?("Searching inside \(apkEntry.fileName)...")
                guard let apkData = try? decompressEntry(handle: handle, entry: apkEntry) else {
                    print("[APKExtractor] Failed to decompress nested entry: \(apkEntry.fileName)")
                    continue
                }

                let tempSplitURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_nested_\(UUID().uuidString).apk")
                try apkData.write(to: tempSplitURL)
                defer { try? FileManager.default.removeItem(at: tempSplitURL) }

                if let splitHandle = try? FileHandle(forReadingFrom: tempSplitURL) {
                    defer { try? splitHandle.close() }
                    if let splitEntries = try? parseZIPEntries(handle: splitHandle) {
                        print("[APKExtractor] Nested package \(apkEntry.fileName) contains \(splitEntries.count) entries.")
                        for se in splitEntries where se.fileName.lowercased().contains(".so") {
                            print("[APKExtractor]   - Nested .so: \(se.fileName) (size: \(se.uncompressedSize))")
                        }
                        let extracted = try extractTargetLibraries(entries: splitEntries, handle: splitHandle, destinationDir: destinationDir, progress: progress)
                        foundLibraries.formUnion(extracted)
                        print("[APKExtractor] Extracted from \(apkEntry.fileName): \(extracted), total found: \(foundLibraries)")
                        if foundLibraries.count >= targetLibraries.count {
                            break
                        }
                    }
                }
            }
        }

        let missing = targetLibraries.filter { !foundLibraries.contains($0) }
        guard missing.isEmpty else {
            print("[APKExtractor] ERROR: Missing libraries \(missing) after searching archive and all nested APKs.")
            throw APKExtractorError.missingLibraries(missing)
        }
    }

    private static func extractTargetLibraries(
        entries: [ZIPEntry],
        handle: FileHandle,
        destinationDir: URL,
        progress: ((String) -> Void)?
    ) throws -> Set<String> {
        var foundLibraries = Set<String>()

        for target in targetLibraries {
            let matchingEntries = entries.filter { $0.fileName.lowercased().hasSuffix(target.lowercased()) }
            print("[APKExtractor] Matching entries for '\(target)': \(matchingEntries.map { $0.fileName })")
            guard let bestEntry = matchingEntries.first(where: { $0.fileName.lowercased().contains("arm64") }) ?? matchingEntries.first else {
                continue
            }

            print("[APKExtractor] Extracting entry '\(bestEntry.fileName)' (\(bestEntry.uncompressedSize) bytes) as '\(target)'...")
            progress?("Extracting \(target)...")
            let libData = try decompressEntry(handle: handle, entry: bestEntry)
            let destFile = destinationDir.appendingPathComponent(target)
            try libData.write(to: destFile)
            print("[APKExtractor] Written \(target) to \(destFile.path) (\(libData.count) bytes)")
            foundLibraries.insert(target)
        }

        return foundLibraries
    }

    private struct ZIPEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: UInt64
    }

    private static func parseZIPEntries(handle: FileHandle) throws -> [ZIPEntry] {
        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 22 else {
            throw APKExtractorError.invalidZIP("Archive too small.")
        }

        let searchRange: UInt64 = min(fileSize, 65536 + 22)
        handle.seek(toFileOffset: fileSize - searchRange)
        guard let tailData = try? handle.readDataToEndOfFile() else {
            throw APKExtractorError.invalidZIP("Failed to read archive footer.")
        }

        var eocdOffsetInTail: Int? = nil
        let tailBytes = [UInt8](tailData)
        if tailBytes.count >= 22 {
            for i in stride(from: tailBytes.count - 22, through: 0, by: -1) {
                if tailBytes[i] == 0x50 && tailBytes[i+1] == 0x4B && tailBytes[i+2] == 0x05 && tailBytes[i+3] == 0x06 {
                    eocdOffsetInTail = i
                    break
                }
            }
        }

        guard let eocdPos = eocdOffsetInTail else {
            throw APKExtractorError.invalidZIP("EOCD signature not found.")
        }

        let eocdData = tailData.subdata(in: eocdPos..<(eocdPos + 22))
        let totalEntries = Int(eocdData.getUInt16(at: 10))
        let cdSize = UInt64(eocdData.getUInt32(at: 12))
        let cdOffset = UInt64(eocdData.getUInt32(at: 16))

        handle.seek(toFileOffset: cdOffset)
        let cdData = handle.readData(ofLength: Int(cdSize))
        guard cdData.count == Int(cdSize) else {
            throw APKExtractorError.invalidZIP("Incomplete Central Directory.")
        }

        var entries = [ZIPEntry]()
        var offset = 0

        for _ in 0..<totalEntries {
            guard offset + 46 <= cdData.count else { break }
            let sig = cdData.getUInt32(at: offset)
            guard sig == 0x02014B50 else { break }

            let compressionMethod = cdData.getUInt16(at: offset + 10)
            let compressedSize = Int(cdData.getUInt32(at: offset + 20))
            let uncompressedSize = Int(cdData.getUInt32(at: offset + 24))
            let fileNameLength = Int(cdData.getUInt16(at: offset + 28))
            let extraLength = Int(cdData.getUInt16(at: offset + 30))
            let commentLength = Int(cdData.getUInt16(at: offset + 32))
            let localHeaderOffset = UInt64(cdData.getUInt32(at: offset + 42))

            let fileNameStart = offset + 46
            guard fileNameStart + fileNameLength <= cdData.count else { break }
            let fileNameData = cdData.subdata(in: fileNameStart..<(fileNameStart + fileNameLength))
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

            entries.append(ZIPEntry(
                fileName: fileName,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))

            offset += 46 + fileNameLength + extraLength + commentLength
        }

        return entries
    }

    private static func decompressEntry(handle: FileHandle, entry: ZIPEntry) throws -> Data {
        handle.seek(toFileOffset: entry.localHeaderOffset)
        let localHeaderData = handle.readData(ofLength: 30)
        guard localHeaderData.count == 30, localHeaderData.getUInt32(at: 0) == 0x04034B50 else {
            throw APKExtractorError.invalidZIP("Bad local header for \(entry.fileName)")
        }

        let localNameLen = Int(localHeaderData.getUInt16(at: 26))
        let localExtraLen = Int(localHeaderData.getUInt16(at: 28))
        let dataOffset = entry.localHeaderOffset + 30 + UInt64(localNameLen) + UInt64(localExtraLen)

        handle.seek(toFileOffset: dataOffset)
        let compressedBytes = handle.readData(ofLength: entry.compressedSize)
        guard compressedBytes.count == entry.compressedSize else {
            throw APKExtractorError.invalidZIP("Incomplete data for \(entry.fileName)")
        }

        if entry.compressionMethod == 0 {
            return compressedBytes
        } else if entry.compressionMethod == 8 {
            var buffer = Data(count: entry.uncompressedSize)
            let decoded = buffer.withUnsafeMutableBytes { dst in
                compressedBytes.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!,
                        entry.uncompressedSize,
                        src.bindMemory(to: UInt8.self).baseAddress!,
                        compressedBytes.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard decoded == entry.uncompressedSize else {
                throw APKExtractorError.extractionFailed("ZLIB decompression returned \(decoded) (expected \(entry.uncompressedSize))")
            }
            return buffer
        } else {
            throw APKExtractorError.extractionFailed("Unsupported compression method \(entry.compressionMethod)")
        }
    }
}

private extension Data {
    func getUInt16(at offset: Int) -> UInt16 {
        let idx = startIndex + offset
        guard idx + 1 < endIndex else { return 0 }
        let b0 = UInt16(self[idx])
        let b1 = UInt16(self[idx + 1])
        return b0 | (b1 << 8)
    }

    func getUInt32(at offset: Int) -> UInt32 {
        let idx = startIndex + offset
        guard idx + 3 < endIndex else { return 0 }
        let b0 = UInt32(self[idx])
        let b1 = UInt32(self[idx + 1])
        let b2 = UInt32(self[idx + 2])
        let b3 = UInt32(self[idx + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
