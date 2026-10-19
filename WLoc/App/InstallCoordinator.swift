import SwiftUI
import UIKit

@MainActor
final class InstallCoordinator: ObservableObject {
    @Published private(set) var status: String?
    @Published private(set) var serving = false
    private let server = InstallHTTPServer()
    private var background = UIBackgroundTaskIdentifier.invalid
    private var expiry: Task<Void, Never>?
    private var generation = UUID()

    func open(_ configuration: InstallConfiguration) async throws {
        await stop()
        let generation = UUID()
        self.generation = generation
        background = UIApplication.shared.beginBackgroundTask(withName: "WLoc configuration transfer") { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                await self.stop(message: "系统已结束临时安装服务。请返回重新开始或使用配置文件导入。")
            }
        }
        guard background != .invalid else { throw WLocError.installationFailed }
        do {
            let resource = try await server.start(content: Data(configuration.content.utf8), fileName: configuration.fileName)
            guard self.generation == generation, !Task.isCancelled else { throw WLocError.installationExpired }
            let link = try configuration.connection.client.importURL(resource: resource)
            serving = true
            status = "等待目标工具导入；返回后将验证连接。临时服务最长 120 秒，系统可能提前结束。"
            expiry = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                guard let self, self.generation == generation else { return }
                await self.stop(message: WLocError.installationExpired.localizedDescription)
            }
            let opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(link, options: [:]) { continuation.resume(returning: $0) }
            }
            guard opened else { throw WLocError.appUnavailable }
        } catch { await stop(); throw error }
    }
    func stop(message: String? = nil) async {
        generation = UUID()
        expiry?.cancel(); expiry = nil
        await server.stop()
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
        serving = false; status = message
    }
    func export(_ configuration: InstallConfiguration) throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WLocInstall", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            let date = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate
            if let date, Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: old) }
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent(configuration.fileName)
        try Data(configuration.content.utf8).write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}

struct InstallFileShare: UIViewControllerRepresentable {
    let file: URL
    let finished: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            Task { @MainActor in finished() }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
