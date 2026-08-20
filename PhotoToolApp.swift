import AppKit
import CryptoKit
import Foundation
import ImageIO
import SwiftUI

enum AppConfig {
    static let serviceLabel = "com.juma.airdrop-heic-converter"
    static let projectDirectory = "/Users/jumafernandez/Documents/ChatGPT/fotosMac"
    static var launchAgentPlist: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(serviceLabel).plist"
    }
}

struct Shell {
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

func humanSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func isImageURL(_ url: URL) -> Bool {
    let allowed = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff"]
    return allowed.contains(url.pathExtension.lowercased())
}

func openInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

@main
struct PhotoToolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ConverterView()
                .tabItem { Label("Convertir HEIC", systemImage: "arrow.triangle.2.circlepath.camera") }
            DuplicateFinderView()
                .tabItem { Label("Duplicadas", systemImage: "rectangle.on.rectangle") }
        }
        .padding(18)
    }
}

struct ConverterView: View {
    @State private var running = false
    @State private var pendingCount = 0
    @State private var folder = URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads")
    @State private var activeWatchFolder = URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads")
    @State private var statusText = "Comprobando..."
    @State private var loadedConfiguredFolder = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var folderName: String {
        if folder.path == "\(NSHomeDirectory())/Downloads" { return "Descargas" }
        if folder.path == "\(NSHomeDirectory())/Pictures" { return "Pictures" }
        return folder.lastPathComponent
    }

    private var selectedFolderIsActive: Bool {
        running && folder.standardizedFileURL.path == activeWatchFolder.standardizedFileURL.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Convertidor AirDrop")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                StatusPill(running: running)
            }

            HStack(spacing: 18) {
                MetricPanel(title: "Carpeta elegida", value: folderName, detail: folder.path)
                MetricPanel(
                    title: "Fotos por convertir",
                    value: "\(pendingCount)",
                    detail: pendingCount == 1 ? "HEIC pendiente" : "HEIC pendientes"
                )
                MetricPanel(title: "Salida", value: ".JPG", detail: "Pregunta antes de borrar HEIC")
            }

            HStack(spacing: 10) {
                Button("Descargas") {
                    setFolder(URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads"))
                }
                Button("Pictures") {
                    setFolder(URL(fileURLWithPath: "\(NSHomeDirectory())/Pictures"))
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Otra carpeta", systemImage: "folder.badge.plus")
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    startService()
                } label: {
                    Label(running ? "Usar esta carpeta" : "Arrancar", systemImage: running ? "checkmark.circle.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolderIsActive)

                Button {
                    stopService()
                } label: {
                    Label("Parar", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!running)

                Button {
                    NSWorkspace.shared.open(folder)
                } label: {
                    Label("Abrir carpeta", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Text(statusText)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            loadConfiguredFolderOnce()
            refresh()
        }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        running = serviceIsRunning()
        if let configuredFolder = configuredWatchFolder() {
            activeWatchFolder = configuredFolder
        }
        pendingCount = countPendingHEIC(in: folder)

        if running {
            if selectedFolderIsActive {
                statusText = "Funcionando. Vigilando \(activeWatchFolder.path)."
            } else {
                statusText = "Funcionando en \(activeWatchFolder.path). Pulsa Usar esta carpeta para cambiar a \(folder.path)."
            }
        } else {
            statusText = "Parado. Elige una carpeta y pulsa Arrancar."
        }
    }

    private func serviceIsRunning() -> Bool {
        let output = Shell.run("/bin/zsh", ["-lc", "launchctl print \"gui/$(id -u)/\(AppConfig.serviceLabel)\" 2>/dev/null | /usr/bin/grep 'state = running' || true"])
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadConfiguredFolderOnce() {
        guard !loadedConfiguredFolder else { return }
        loadedConfiguredFolder = true
        if let configuredFolder = configuredWatchFolder() {
            folder = configuredFolder
            activeWatchFolder = configuredFolder
        }
    }

    private func configuredWatchFolder() -> URL? {
        guard let data = FileManager.default.contents(atPath: AppConfig.launchAgentPlist) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        guard let environment = plist["EnvironmentVariables"] as? [String: String],
              let path = environment["AIRDROP_CONVERT_DIR"],
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func setFolder(_ newFolder: URL) {
        folder = newFolder
        pendingCount = countPendingHEIC(in: newFolder)
        refresh()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }

    private func countPendingHEIC(in folder: URL) -> Int {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return urls.filter { url in
            guard url.pathExtension.lowercased() == "heic" else { return false }
            let base = url.deletingPathExtension()
            let counterparts = ["JPG", "jpg", "PNG", "png"].map { base.appendingPathExtension($0) }
            return !counterparts.contains { manager.fileExists(atPath: $0.path) }
        }.count
    }

    private func startService() {
        _ = Shell.run("/bin/zsh", ["-lc", "cd \(AppConfig.projectDirectory.shellQuoted) && AIRDROP_CONVERT_DIR=\(folder.path.shellQuoted) ./install.sh"])
        refresh()
    }

    private func stopService() {
        _ = Shell.run("/bin/zsh", ["-lc", "launchctl bootout \"gui/$(id -u)\" \(AppConfig.launchAgentPlist.shellQuoted) >/dev/null 2>&1 || true"])
        refresh()
    }
}

struct StatusPill: View {
    let running: Bool

    var body: some View {
        Label(running ? "Funcionando" : "Parado", systemImage: running ? "checkmark.circle.fill" : "pause.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(running ? .green : .orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
    }
}

struct MetricPanel: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum DuplicateKind: String {
    case exact = "Iguales"
    case visual = "Parecidas"
}

struct PhotoFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let exactHash: String
    let visualHash: UInt64?
}

struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID()
    let kind: DuplicateKind
    let files: [PhotoFile]

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var title: String {
        "\(files.count) fotos \(kind.rawValue.lowercased())"
    }
}

struct DuplicateFinderView: View {
    @State private var folder = URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads")
    @State private var recursive = false
    @State private var scanning = false
    @State private var scanMessage = "Elige una carpeta y pulsa Buscar."
    @State private var groups: [DuplicateGroup] = []
    @State private var selectedGroupID: DuplicateGroup.ID?
    @State private var selectedForTrash = Set<PhotoFile.ID>()
    @State private var confirmTrash = false

    private var selectedGroup: DuplicateGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    private var selectedSavings: Int64 {
        groups.flatMap(\.files)
            .filter { selectedForTrash.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Buscar fotos duplicadas")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Text("Espacio que ganarías: \(humanSize(selectedSavings))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selectedSavings > 0 ? .green : .secondary)
            }

            HStack(spacing: 10) {
                Button("Descargas") { folder = URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads") }
                Button("Pictures") { folder = URL(fileURLWithPath: "\(NSHomeDirectory())/Pictures") }
                Button {
                    chooseFolder()
                } label: {
                    Label("Otra carpeta", systemImage: "folder.badge.plus")
                }
                Toggle("Buscar dentro de subcarpetas", isOn: $recursive)
                    .toggleStyle(.checkbox)
                Spacer()
                Button {
                    scan()
                } label: {
                    Label(scanning ? "Buscando..." : "Buscar", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanning)
            }

            Text(folder.path)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scanMessage)
                        .font(.system(size: 14, weight: .medium))
                    if scanning {
                        ProgressView()
                    }
                    List(groups, selection: $selectedGroupID) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(humanSize(group.totalSize)) en total")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minWidth: 260, maxWidth: 320)

                Divider()

                Group {
                    if let group = selectedGroup {
                        DuplicateGroupDetail(
                            group: group,
                            selectedForTrash: $selectedForTrash
                        )
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 42))
                                .foregroundStyle(.secondary)
                            Text("Selecciona un grupo para previsualizar.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    confirmTrash = true
                } label: {
                    Label("Mover seleccionadas a la Papelera", systemImage: "trash")
                }
                .disabled(selectedSavings == 0)
            }
        }
        .alert("¿Mover a la Papelera?", isPresented: $confirmTrash) {
            Button("Cancelar", role: .cancel) {}
            Button("Mover a la Papelera", role: .destructive) {
                moveSelectedToTrash()
            }
        } message: {
            Text("Ganarías \(humanSize(selectedSavings)). No se borra definitivamente: van a la Papelera.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
        }
    }

    private func scan() {
        scanning = true
        groups = []
        selectedGroupID = nil
        selectedForTrash = []
        scanMessage = "Buscando fotos..."

        let selectedFolder = folder
        let includeSubfolders = recursive
        Task.detached(priority: .userInitiated) {
            let result = DuplicateScanner.scan(folder: selectedFolder, recursive: includeSubfolders) { message in
                Task { @MainActor in
                    scanMessage = message
                }
            }
            await MainActor.run {
                groups = result
                selectedGroupID = result.first?.id
                selectedForTrash = Set(result.flatMap { defaultTrashSelection(for: $0) })
                scanMessage = result.isEmpty
                    ? "No se encontraron duplicadas."
                    : "\(result.count) grupos encontrados."
                scanning = false
            }
        }
    }

    private func defaultTrashSelection(for group: DuplicateGroup) -> [PhotoFile.ID] {
        let keep = preferredFileToKeep(in: group)
        return group.files.filter { $0.id != keep.id }.map(\.id)
    }

    private func preferredFileToKeep(in group: DuplicateGroup) -> PhotoFile {
        let ranked = group.files.sorted {
            let leftScore = keepScore($0)
            let rightScore = keepScore($1)
            if leftScore != rightScore { return leftScore > rightScore }
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.modified > $1.modified
        }
        return ranked[0]
    }

    private func keepScore(_ file: PhotoFile) -> Int {
        switch file.url.pathExtension.lowercased() {
        case "jpg", "jpeg": return 40
        case "png": return 30
        case "heic", "heif": return 20
        default: return 10
        }
    }

    private func moveSelectedToTrash() {
        let ids = selectedForTrash
        let selectedURLs = groups.flatMap(\.files)
            .filter { ids.contains($0.id) }
            .map(\.url)

        for url in selectedURLs {
            var trashedURL: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            } catch {
                NSSound.beep()
            }
        }

        groups = groups.compactMap { group in
            let remaining = group.files.filter { !ids.contains($0.id) }
            return remaining.count > 1 ? DuplicateGroup(kind: group.kind, files: remaining) : nil
        }
        selectedForTrash = []
        selectedGroupID = groups.first?.id
        scanMessage = groups.isEmpty ? "Duplicadas movidas a la Papelera." : "\(groups.count) grupos pendientes."
    }
}

struct DuplicateGroupDetail: View {
    let group: DuplicateGroup
    @Binding var selectedForTrash: Set<PhotoFile.ID>

    private var groupSavings: Int64 {
        group.files
            .filter { selectedForTrash.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(group.kind == .exact ? "Archivos iguales" : "Fotos parecidas")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Selecciona lo que quieres mover a la Papelera.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Ganarías \(humanSize(groupSavings))")
                    .foregroundStyle(groupSavings > 0 ? .green : .secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(group.files) { file in
                        DuplicateFileRow(
                            file: file,
                            selected: selectedForTrash.contains(file.id),
                            onToggle: {
                                if selectedForTrash.contains(file.id) {
                                    selectedForTrash.remove(file.id)
                                } else {
                                    selectedForTrash.insert(file.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DuplicateFileRow: View {
    let file: PhotoFile
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: file.url)
                .frame(width: 96, height: 72)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(humanSize(file.size)) · \(file.url.deletingLastPathComponent().path)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                openInFinder(file.url)
            } label: {
                Label("Ver", systemImage: "eye")
            }

            Toggle("Papelera", isOn: Binding(
                get: { selected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            image = NSImage(contentsOf: url)
        }
    }
}

struct DuplicateScanner {
    static func scan(folder: URL, recursive: Bool, progress: @escaping (String) -> Void) -> [DuplicateGroup] {
        let urls = imageFiles(in: folder, recursive: recursive)
        progress("\(urls.count) fotos encontradas. Comparando...")

        let files = urls.compactMap { photoFile(for: $0) }
        var groups: [DuplicateGroup] = []
        var exactGroupedIDs = Set<PhotoFile.ID>()

        let exactGroups = Dictionary(grouping: files, by: \.exactHash)
            .values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(kind: .exact, files: $0.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }) }

        for group in exactGroups {
            group.files.forEach { exactGroupedIDs.insert($0.id) }
        }
        groups.append(contentsOf: exactGroups)

        let visualCandidates = files.filter { !exactGroupedIDs.contains($0.id) && $0.visualHash != nil }
        let visualGroups = Dictionary(grouping: visualCandidates, by: { $0.visualHash! })
            .values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(kind: .visual, files: $0.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }) }

        groups.append(contentsOf: visualGroups)
        return groups.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind == .exact
            }
            return $0.totalSize > $1.totalSize
        }
    }

    private static func imageFiles(in folder: URL, recursive: Bool) -> [URL] {
        let manager = FileManager.default
        if recursive {
            guard let enumerator = manager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }
            return enumerator.compactMap { $0 as? URL }.filter(isImageURL)
        }

        guard let urls = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter(isImageURL)
    }

    private static func photoFile(for url: URL) -> PhotoFile? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize else { return nil }
        guard let exactHash = sha256(url: url) else { return nil }
        return PhotoFile(
            url: url,
            size: Int64(size),
            modified: values?.contentModificationDate ?? .distantPast,
            exactHash: exactHash,
            visualHash: averageHash(url: url)
        )
    }

    private static func sha256(url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func averageHash(url: URL) -> UInt64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 16
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var hash: UInt64 = 0
        for pixel in pixels {
            hash <<= 1
            if Int(pixel) >= average {
                hash |= 1
            }
        }
        return hash
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
