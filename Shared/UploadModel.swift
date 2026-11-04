import Foundation

@MainActor
final class UploadModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case uploading
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentFile = ""
    @Published private(set) var fileIndex = 0
    @Published private(set) var fileCount = 0
    @Published private(set) var sentBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var uploadedNames: [String] = []

    private var task: Task<Void, Never>?

    var fraction: Double {
        totalBytes > 0 ? min(1, Double(sentBytes) / Double(totalBytes)) : 0
    }

    func start(files: [URL], server: Server, destination: Destination) {
        guard phase != .uploading else { return }
        let sizes = files.map { Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        totalBytes = sizes.reduce(0, +)
        sentBytes = 0
        fileCount = files.count
        fileIndex = 0
        uploadedNames = []
        phase = .uploading

        task = Task { [weak self] in
            do {
                let client = try RemoteClientFactory.make(for: server)
                defer { Task { await client.disconnect() } }
                try await client.connect()
                let dir = RemotePath.normalize(destination.path)
                if !dir.isEmpty { try await client.makeDirectories(dir) }

                var done: Int64 = 0
                for (i, file) in files.enumerated() {
                    try Task.checkCancellation()
                    let name = try await client.availableName(for: file.lastPathComponent, in: dir)
                    self?.fileIndex = i + 1
                    self?.currentFile = name
                    let base = done
                    try await client.upload(file: file, to: RemotePath.join(dir, name)) { sent in
                        Task { @MainActor in self?.sentBytes = base + sent }
                    }
                    try Task.checkCancellation()
                    done += sizes[i]
                    self?.sentBytes = done
                    self?.uploadedNames.append(name)
                }
                var cfg = ConfigStore.shared.config
                cfg.lastDestinationID = destination.id
                ConfigStore.shared.config = cfg
                self?.phase = .done
            } catch is CancellationError {
                self?.phase = .failed(RemoteError.cancelled.localizedDescription)
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func reset() {
        phase = .idle
    }
}
