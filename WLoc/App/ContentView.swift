import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var editing: Place?
    @State private var confirmDisable = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 38)).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(statusTitle).font(.headline)
                            if let remote = store.remote {
                                Text(remote.coordinateText).font(.subheadline.monospacedDigit())
                            } else {
                                Text(store.connection == nil ? "首次连接后，点选收藏即可提交坐标" : "下拉刷新，读取当前配置")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let date = store.checkedAt {
                                Text("读取于 \(date.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if store.busy { ProgressView().accessibilityLabel("正在连接服务") }
                    }.padding(.vertical, 8)
                    if let notice = store.notice {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    if store.connection == nil {
                        Button("连接现有选点服务") { settings = true }
                    }
                } header: { Text("服务端配置") } footer: {
                    Text("保存坐标后，Surge 会在后续 WLOC 请求中读取。这里不代表系统 GPS 已切换，请在地图中确认。")
                }

                Section {
                    if store.places.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("添加你的第一个地点", systemImage: "mappin.and.ellipse").font(.headline)
                            Text("输入名称和 WGS-84 经纬度，之后轻点地点即可提交。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("添加地点") { addPlace() }.padding(.top, 4)
                        }.padding(.vertical, 12)
                    }
                    ForEach(store.places) { place in
                        HStack(spacing: 12) {
                            Button {
                                Task { await store.apply(place) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: store.remote?.matches(place) == true ? "checkmark.circle.fill" : "mappin.circle")
                                        .font(.title2).foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(place.name).foregroundStyle(.primary).font(.headline)
                                        Text(place.coordinateText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.busy || store.connection == nil)
                            .accessibilityLabel("提交地点，\(place.name)，\(place.coordinateText)")

                            Button { editing = place } label: { Image(systemName: "pencil.circle").font(.title3) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("编辑\(place.name)")
                        }.padding(.vertical, 5)
                    }
                    .onDelete(perform: store.delete)
                    .onMove(perform: store.move)
                    if let remote = store.remote {
                        Button {
                            editing = Place(name: "", latitude: remote.latitude, longitude: remote.longitude,
                                            horizontalAccuracy: remote.horizontalAccuracy ?? 39)
                        } label: { Label("收藏当前配置坐标", systemImage: "star.badge.plus") }
                    }
                } header: {
                    HStack {
                        Text("常用地点")
                        Spacer()
                        Text("\(store.places.count) 个")
                    }
                } footer: { Text("轻点地点提交；点铅笔编辑；左滑删除；点右上角“编辑”调整顺序。") }

                if store.connection != nil {
                    Section {
                        Button { confirmDisable = true } label: {
                            Label("关闭虚拟定位", systemImage: "location.slash")
                        }.disabled(store.busy || store.remote?.enabled == false)
                        Button { Task { await store.refresh() } } label: {
                            Label("刷新服务端配置", systemImage: "arrow.clockwise")
                        }.disabled(store.busy)
                    } footer: {
                        Text("关闭后服务将返回 enabled=false。系统可能继续使用缓存坐标，需按你现有的生效步骤操作。")
                    }
                }
            }
            .navigationTitle("WLoc 常用定位")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("服务设置")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button { addPlace() } label: { Image(systemName: "plus") }.accessibilityLabel("添加地点")
                }
            }
            .refreshable { await store.refresh() }
            .task { if store.checkedAt == nil { await store.refreshIfConnected() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await store.refreshIfConnected() } }
            }
            .sheet(isPresented: $settings) { ConnectionView() }
            .sheet(item: $editing) { place in PlaceEditor(place: place) }
            .confirmationDialog("关闭服务端虚拟定位？", isPresented: $confirmDisable, titleVisibility: .visible) {
                Button("关闭虚拟定位", role: .destructive) { Task { await store.disable() } }
            } message: { Text("关闭后仍需刷新系统定位，并打开地图确认。") }
            .alert("提示", isPresented: Binding(get: { store.alert != nil && !settings && editing == nil }, set: { if !$0 { store.alert = nil } })) {
                Button("知道了", role: .cancel) { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }

    private var statusTitle: String {
        guard store.connection != nil else { return "尚未连接" }
        guard let remote = store.remote else { return "配置待确认" }
        return remote.enabled ? "服务端虚拟定位已开启" : "服务端虚拟定位已关闭"
    }

    private func addPlace() { editing = Place(name: "", latitude: 0, longitude: 0) }
}

extension AppStore {
    func refreshIfConnected() async { if connection != nil { await refresh() } }
}

