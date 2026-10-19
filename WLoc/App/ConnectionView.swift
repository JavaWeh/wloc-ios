import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                if let connection = store.connection {
                    Section("已连接") {
                        Text(connection.displayAddress).textSelection(.enabled)
                        Text("Token 已存入本机钥匙串").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    SecureField("粘贴含 token 的完整 HTTPS 链接", text: $link)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { if await store.connect(link: link) { link = ""; dismiss() } }
                    } label: {
                        HStack { Text("验证并保存连接"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                } header: { Text(store.connection == nil ? "连接现有服务" : "更换服务") } footer: {
                    Text("从原选点网页复制地址（含 ?token=…），也可使用 Surge 中配置的 loc.json 链接。只支持参考项目的 HTTPS 选点服务；验证成功后保存。无需在聊天中提供 token。")
                }
                Section("Surge 配合方式") {
                    Text("App 与 Surge 必须使用同一个服务地址、同一个 token。App 将地点写入服务，Surge 通过 configUrl 读取。")
                    Text("请保持当前已验证可用的 Surge、MITM 和 WLOC 配置。App 无法清除 iOS 定位缓存，也无法自行重启系统定位服务。")
                }
                if store.connection != nil {
                    Section {
                        Button("移除本机连接", role: .destructive) { confirmDisconnect = true }.disabled(store.busy)
                    } footer: { Text("保留本机收藏。移除连接不会关闭服务端虚拟定位；需要关闭时，请先在首页操作。") }
                }
            }
            .navigationTitle("服务设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(store.busy) } }
            .interactiveDismissDisabled(store.busy)
            .confirmationDialog("移除本机保存的服务地址和 token？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("移除连接", role: .destructive) { store.disconnect() }
            }
            .alert("连接未完成", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
                Button("知道了", role: .cancel) { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }
}
