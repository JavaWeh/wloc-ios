import SwiftUI
import Security

enum CredentialVault {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "WLoc.localConnection.v2",
         kSecAttrAccount as String: "primary"]
    }

    static func read() throws -> Connection? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.access }
        return try JSONDecoder().decode(Connection.self, from: data)
    }

    static func save(_ connection: Connection) throws {
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw VaultError.access }
        var entry = query
        attributes.forEach { entry[$0.key] = $0.value }
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw VaultError.access }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.access }
    }

    enum VaultError: LocalizedError {
        case access
        var errorDescription: String? { "无法访问钥匙串，请解锁设备后重试。" }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var places: [Place] = []
    @Published private(set) var connection: Connection?
    @Published private(set) var remote: RemoteLocation?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var busy = false
    @Published var alert: String?
    @Published private(set) var notice: String?
    private let favorites: FavoritesStore

    init() {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("places.json")
        favorites = FavoritesStore(file: file, options: [.atomic, .completeFileProtection])
        do {
            places = try favorites.load()
            if favorites.recoveryFile != nil {
                alert = "原收藏文件损坏，已在 Documents 中保留 places-recovery 备份，可以重新添加收藏。"
            }
        } catch {
            alert = WLocError.storageReadOnly.localizedDescription
        }
        // A damaged favorites file must not prevent loading an independent pairing.
        do { connection = try CredentialVault.read() }
        catch { alert = alert ?? "无法读取本机配对，请解锁设备或重新配对。" }
    }

    private func persist(_ next: [Place]) throws {
        try favorites.save(next)
        places = next
    }

    @discardableResult
    func save(_ place: Place) -> Bool {
        do {
            try place.validate()
            var next = places
            if let index = next.firstIndex(where: { $0.id == place.id }) { next[index] = place }
            else { next.append(place) }
            try persist(next)
            return true
        } catch { show(error); return false }
    }

    func delete(at offsets: IndexSet) {
        var next = places
        next.remove(atOffsets: offsets)
        do { try persist(next) } catch { show(error) }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        var next = places
        next.move(fromOffsets: offsets, toOffset: destination)
        do { try persist(next) } catch { show(error) }
    }

    func connect(key: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let candidate = try Connection(key: key)
            let location = try await LocationClient(connection: candidate).fetch()
            try CredentialVault.save(candidate)
            connection = candidate
            remote = location
            checkedAt = Date()
            notice = "Surge 本机配对成功"
            return true
        } catch { show(error); return false }
    }

    func disconnect() {
        guard !busy else { return }
        do {
            try CredentialVault.remove()
            connection = nil
            remote = nil
            checkedAt = nil
            notice = nil
        } catch { show(error) }
    }

    func refresh() async {
        await perform { client in
            let location = try await client.fetch()
            self.notice = "已读取 Surge 本机配置"
            return location
        }
    }

    func apply(_ place: Place) async {
        await perform { client in
            let location = try await client.apply(place)
            self.notice = "已保存「\(place.name)」，请按原有步骤刷新系统定位"
            return location
        }
    }

    func disable() async {
        await perform { client in
            let location = try await client.disable()
            self.notice = "已关闭本机虚拟定位，请刷新系统定位并在地图确认"
            return location
        }
    }

    private func perform(_ operation: (LocationClient) async throws -> RemoteLocation) async {
        guard !busy else { return }
        guard let connection else { alert = "请先完成 Surge 本机配对。"; return }
        busy = true
        notice = nil
        defer { busy = false }
        do {
            remote = try await operation(LocationClient(connection: connection))
            checkedAt = Date()
        } catch {
            // A timeout after POST does not prove the server rejected the change.
            remote = nil
            checkedAt = nil
            show(error)
        }
    }

    private func show(_ error: Error) {
        if let known = error as? WLocError { alert = known.localizedDescription }
        else if let known = error as? CredentialVault.VaultError { alert = known.localizedDescription }
        else if error is URLError {
            alert = "未能读取 Surge 本机接口。请确认 Surge 正在运行，配套模块及 MITM 已启用，证书已信任。若刚提交了地点，请刷新核对保存状态。"
        } else { alert = "操作未完成，请检查本地储存空间或服务配置后重试。" }
    }
}

