import SwiftUI

private struct InstallShareItem: Identifiable { let id = UUID(); let file: URL }

struct ConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var installer = InstallCoordinator()
    @State private var candidate: Connection?
    @State private var share: InstallShareItem?
    @State private var installing = false
    @State private var awaitingReturn = false
    @State private var confirmDisconnect = false
    @State private var legacyKey = ""
    private var client: ProxyClient { store.selectedClient }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择正在使用的工具") {
                    Picker("工具", selection: Binding(get: { client }, set: { value in
                        store.select(value); candidate = nil; awaitingReturn = false
                        Task { await installer.stop() }
                    })) {
                        ForEach(ProxyClient.allCases) { Text($0.title).tag($0) }
                    }.disabled(installing || store.busy)
                    Text(store.connection == nil ? "尚未配对 \(client.title)" : "已保存配对：\(store.connection!.displayAddress)")
                    Text("五端适配已提供；快捷导入、重启后的配置保留和实际定位效果均待真机验证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if client.prefersFileImport { exportButton; quickButton }
                    else { quickButton; exportButton }
                    Text(client.importInstructions)
                    if client.prefersFileImport {
                        Text("建议优先文件导入；快捷安装为实验功能。若分享列表没有该工具，请先保存到“文件”，再在工具中选择本地导入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("专属配置已填好本机配对信息，无需复制密钥。文件含密钥，请只导入本机对应工具。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let status = installer.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if installer.serving { Button("结束临时安装服务") { Task { await installer.stop() } } }
                } header: { Text("1. 安装专属定位组件") } footer: {
                    Text("确认安装并启用组件，停用其他 WLOC 定位模块。保留已有证书；首次仍须在系统设置安装并信任目标工具的 MITM 证书。不会替换节点、订阅或主配置。")
                }
                Section {
                    Button { Task { await verify() } } label: {
                        HStack { Text("验证 \(client.title) 本机连接"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(store.busy || installing)
                    Text("打开目标工具不代表安装完成；本机接口和工具身份验证通过后才会显示已连接。之后点选收藏即可写入，无需重复导入。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("2. 返回 App 验证") }
                if client == .surge {
                    DisclosureGroup("连接已有旧版 Surge 模块") {
                        SecureField("旧模块的配对密钥", text: $legacyKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("验证旧版连接") {
                            Task {
                                do { _ = await store.connect(try Connection(key: legacyKey)) }
                                catch { store.alert = WLocError.missingToken.localizedDescription }
                            }
                        }.disabled(store.busy || installing || legacyKey.isEmpty)
                        Text("原有配对升级后仍可使用；安装新版组件时须停用旧模块。")
                    }
                }
                Section("开源与限制") {
                    Text("无需自建后台。临时服务仅用于安装文件；已保存的坐标由当前工具独立持有。App 无法清除 iOS 定位缓存，切换后需按原有步骤刷新，并在地图确认。")
                    Link("完整源代码与说明", destination: URL(string: "https://github.com/JavaWeh/wloc-ios")!)
                    NavigationLink("查看 AGPL-3.0 许可证") {
                        ScrollView { Text(licenseText).font(.caption.monospaced()).padding() }.navigationTitle("AGPL-3.0")
                    }
                }
                if store.connection != nil || store.profiles.pending[client.rawValue] != nil {
                    Section {
                        Button("移除此工具的配对", role: .destructive) { confirmDisconnect = true }.disabled(store.busy || installing)
                    } footer: { Text("保留收藏和其他工具的配对，不会关闭工具中已保存的虚拟定位；需要关闭时先在首页操作。") }
                }
            }
            .navigationTitle("本机配对与安装").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(store.busy || installing) } }
            .sheet(item: $share) { item in InstallFileShare(file: item.file) { share = nil } }
            .onDisappear { Task { await installer.stop() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active && awaitingReturn && !installing && !store.busy {
                    awaitingReturn = false
                    Task { await verify() }
                }
            }
            .interactiveDismissDisabled(store.busy || installing)
            .confirmationDialog("移除 \(client.title) 配对？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("移除配对", role: .destructive) { store.disconnect(); candidate = nil; Task { await installer.stop() } }
            }
            .alert("配对与安装提示", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
                Button("知道了", role: .cancel) { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }
    private var quickButton: some View {
        Button {
            Task {
                installing = true
                defer { installing = false }
                do {
                    let configuration = try configuration()
                    awaitingReturn = true
                    try await installer.open(configuration)
                } catch {
                    awaitingReturn = false
                    store.alert = (error as? WLocError)?.localizedDescription ?? WLocError.installationFailed.localizedDescription
                }
            }
        } label: { Label("快捷安装到 \(client.title)（实验）", systemImage: "arrow.up.forward.app") }
        .disabled(installing || store.busy)
    }
    private var exportButton: some View {
        Button {
            do { share = InstallShareItem(file: try installer.export(configuration())); awaitingReturn = true }
            catch { store.alert = (error as? WLocError)?.localizedDescription ?? "配置文件导出失败，请检查储存空间。" }
        } label: { Label("导出专属配置文件", systemImage: "square.and.arrow.up") }
        .disabled(installing || store.busy)
    }
    private func configuration() throws -> InstallConfiguration {
        let draft = try store.prepareConnection()
        candidate = draft
        return try InstallConfiguration(connection: draft, revision: Bundle.main.object(forInfoDictionaryKey: "WLocScriptRevision") as? String ?? "")
    }
    private func verify() async {
        let target = candidate ?? store.profiles.pending[client.rawValue] ?? store.connection
        guard let target else { store.alert = "请先安装此工具的专属配置，再验证连接。"; return }
        if await store.connect(target) {
            awaitingReturn = false
            await installer.stop(message: "连接验证成功；已结束临时安装服务。")
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "https://www.gnu.org/licenses/agpl-3.0.html" }
        return text
    }
}
