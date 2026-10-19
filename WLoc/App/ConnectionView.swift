import SwiftUI
import UIKit

struct ConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var copied = false
    @State private var confirmDisconnect = false
    private let moduleURL = URL(string: "https://raw.githubusercontent.com/JavaWeh/wloc-ios/main/Surge/WLoc-Native.sgmodule")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("无需自建后台", systemImage: "iphone")
                    Text("App 解析并收藏地点，Surge 在这台手机内保存坐标、改写 WLOC。App 退出后，已写入 Surge 的坐标仍保留。")
                        .font(.subheadline)
                }
                Section("1. 复制本机配对密钥") {
                    SecureField("仅英文字母和数字，至少 16 位", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(copied ? "密钥已复制" : "复制配对密钥") {
                        UIPasteboard.general.string = key
                        copied = true
                    }
                    Text("密钥用于防止其他网页随意更改本机坐标。请只粘贴到 Surge 模块的 key 参数，不要公开。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Link("打开配套 Surge 模块", destination: moduleURL)
                    Button("复制模块安装链接") { UIPasteboard.general.string = moduleURL.absoluteString }
                    Text("Surge → 模块 → 安装新模块，粘贴上面的模块链接。打开模块参数，将 key 设为第 1 步复制的密钥。")
                    Text("启用本模块，并停用其他 WLOC 响应改写模块，避免同时处理同一个定位响应。保留并信任现有 MITM 证书。")
                } header: { Text("2. 在 Surge 安装模块（只需一次）") }
                Section {
                    Button {
                        Task { if await store.connect(key: key) { dismiss() } }
                    } label: {
                        HStack { Text("验证 Surge 本机连接"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(store.busy || key.count < 16)
                    if store.connection != nil { Text("已配对：\(store.connection!.displayAddress)").font(.caption) }
                } header: { Text("3. 返回 App 验证") } footer: {
                    Text("配套模块会在手机本机响应控制请求，不需要选点网站、服务器、账户或后台 token。首次未选位置时默认关闭改写。")
                }
                Section("开源与限制") {
                    Text("App 无法清除 iOS 定位缓存。切换后请继续采用你现有的定位生效步骤，并在系统地图确认。")
                    Link("完整源代码与使用说明", destination: URL(string: "https://github.com/JavaWeh/wloc-ios")!)
                    Link("AGPL-3.0 许可证与上游署名", destination: URL(string: "https://github.com/JavaWeh/wloc-ios/blob/main/THIRD_PARTY.md")!)
                    NavigationLink("查看许可证") { ScrollView { Text(licenseText).font(.caption.monospaced()).padding() }.navigationTitle("AGPL-3.0") }
                }
                if store.connection != nil {
                    Section {
                        Button("移除本机配对", role: .destructive) { confirmDisconnect = true }.disabled(store.busy)
                    } footer: { Text("保留收藏，不会自动关闭 Surge 中已保存的虚拟定位；需要关闭时先在首页操作。") }
                }
            }
            .navigationTitle("Surge 本机配对").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(store.busy) } }
            .onAppear { if key.isEmpty { key = store.connection?.key ?? UUID().uuidString.replacingOccurrences(of: "-", with: "") } }
            .interactiveDismissDisabled(store.busy)
            .confirmationDialog("移除本机配对信息？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("移除配对", role: .destructive) { store.disconnect() }
            }
            .alert("配对未完成", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
                Button("知道了", role: .cancel) { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可证：https://www.gnu.org/licenses/agpl-3.0.html" }
        return text
    }
}
