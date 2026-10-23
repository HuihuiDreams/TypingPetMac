import Foundation

struct StagedUpdate: Equatable {
    let manifest: UpdateManifest
    let app: URL
    let folder: URL
}

// Downloads and checks an update, then swaps the bundle from a helper after the app quits.
enum UpdateInstaller {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    static func updatesFolder(bundleIdentifier: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static func fetchManifest(configuration: UpdateConfiguration, session: URLSession) async throws -> UpdateManifest {
        let (data, response) = try await session.data(from: configuration.feedURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.invalidFeed("업데이트 서버가 응답하지 않아요.")
        }
        let manifest: UpdateManifest
        do { manifest = try JSONDecoder().decode(UpdateManifest.self, from: data) } catch {
            throw UpdateError.invalidFeed("업데이트 정보를 읽지 못했어요.")
        }
        try UpdateVerifier.validate(manifest, configuration: configuration)
        return manifest
    }

    static func stage(_ manifest: UpdateManifest, configuration: UpdateConfiguration, session: URLSession) async throws -> StagedUpdate {
        let folder = updatesFolder(bundleIdentifier: configuration.bundleIdentifier)
            .appendingPathComponent("\(manifest.build)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let (download, response) = try await session.download(from: manifest.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.installFailed("업데이트 파일을 내려받지 못했어요.")
            }
            let archive = folder.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: archive)
            try UpdateVerifier.verifyArchive(
                Data(contentsOf: archive, options: .mappedIfSafe),
                manifest: manifest,
                publicKey: configuration.publicKey
            )
            let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path], failure: "업데이트 압축을 풀지 못했어요.")
            let apps = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            guard apps.count == 1, let app = apps.first else { throw UpdateError.rejected("업데이트 안에 앱이 하나여야 해요.") }
            try UpdateVerifier.verifyApp(at: app, manifest: manifest, configuration: configuration)
            if configuration.profile == .production, configuration.teamIdentifier != nil {
                try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path], failure: "업데이트 앱이 공증되지 않았어요.")
            }
            return StagedUpdate(manifest: manifest, app: app, folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func installTarget(for bundleURL: URL) throws -> URL {
        if bundleURL.path.contains("/AppTranslocation/") {
            throw UpdateError.unavailable("앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행하면 업데이트할 수 있어요.")
        }
        let parent = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent), FileManager.default.isWritableFile(atPath: bundleURL.path) else {
            throw UpdateError.unavailable("앱이 있는 폴더에 쓸 권한이 없어요.")
        }
        return bundleURL
    }

    // The helper outlives this process. It restores the previous bundle if the swap fails.
    static func launchHelper(for staged: StagedUpdate, target: URL, relaunch: Bool) throws {
        let script = staged.folder.appendingPathComponent("install.sh")
        try helperScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            target.path,
            staged.app.path,
            relaunch ? "1" : "0",
            staged.folder.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func logURL(in folder: URL) -> URL { folder.appendingPathComponent("install.log") }

    private static func run(_ executable: String, _ arguments: [String], failure: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.rejected(failure) }
    }

    static let helperScript = """
    #!/bin/zsh
    pid="$1" target="$2" staged="$3" relaunch="$4" folder="$5"
    exec >>"$folder/install.log" 2>&1
    for _ in {1..300}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo "FAILED: the app did not quit"
        exit 1
    fi
    backup="$folder/previous.app"
    if ! mv "$target" "$backup"; then
        echo "FAILED: cannot move the current app"
        exit 1
    fi
    if ! mv "$staged" "$target"; then
        echo "FAILED: cannot install the update, restoring"
        rm -rf "$target"
        mv "$backup" "$target"
        [[ "$relaunch" == 1 ]] && open "$target"
        exit 1
    fi
    xattr -dr com.apple.quarantine "$target" 2>/dev/null
    rm -rf "$backup"
    echo "INSTALLED: $target"
    [[ "$relaunch" == 1 ]] && open "$target"
    exit 0
    """
}
