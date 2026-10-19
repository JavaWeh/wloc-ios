import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var importing = false
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
                                Text(store.connection == nil ? "先收藏地点，再完成一次 Surge 本机配对" : "下拉刷新，读取 Surge 本机坐标")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let date = store.checkedAt {
                                Text("读取于 \(date.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if store.busy { ProgressView().accessibilityLabel("正在连接 Surge") }
                    }.padding(.vertical, 8)
                    if let notice = store.notice {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    if store.connection == nil {
                        Button("Surge 本机配对（无需后台）") { settings = true }
                    }
                } header: { Text("Surge 本机配置") } footer: {
                    Text("写入本机后，Surge 在后续 WLOC 请求中读取。App 可关闭，无需后台服务器。定位是否生效请在系统地图中确认。")
                }

                Section {
                    Button { importing = true } label: { Label("粘贴地图链接 / App 地图选点", systemImage: "map.fill") }
                    Button { addPlace() } label: { Label("手动输入 WGS-84 坐标", systemImage: "number") }
                } header: { Text("标记新地点") }

                Section {
                    if store.places.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("添加你的第一个地点", systemImage: "mappin.and.ellipse").font(.headline)
                            Text("复制苹果地图、高德、Google Maps 链接，或直接在 App 地图选点。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("添加地点") { importing = true }.padding(.top, 4)
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
                            Label("刷新 Surge 本机配置", systemImage: "arrow.clockwise")
                        }.disabled(store.busy)
                    } footer: {
                        Text("关闭后服务将返回 enabled=false。系统可能继续使用缓存坐标，需按你现有的生效步骤操作。")
                    }
                }
            }
            .navigationTitle("WLoc 常用定位")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Surge 本机配对")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("导入地图地点")
                }
            }
            .refreshable { await store.refresh() }
            .task { if store.checkedAt == nil { await store.refreshIfConnected() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await store.refreshIfConnected() } }
            }
            .sheet(isPresented: $settings) { ConnectionView() }
            .sheet(isPresented: $importing) { ImportPlaceView() }
            .sheet(item: $editing) { place in PlaceEditor(place: place) }
            .confirmationDialog("关闭 Surge 本机虚拟定位？", isPresented: $confirmDisable, titleVisibility: .visible) {
                Button("关闭虚拟定位", role: .destructive) { Task { await store.disable() } }
            } message: { Text("关闭后仍需刷新系统定位，并打开地图确认。") }
            .alert("提示", isPresented: Binding(get: { store.alert != nil && !settings && !importing && editing == nil }, set: { if !$0 { store.alert = nil } })) {
                Button("知道了", role: .cancel) { store.alert = nil }
            } message: { Text(store.alert ?? "") }
        }
    }

    private var statusTitle: String {
        guard store.connection != nil else { return "尚未配对 Surge" }
        guard let remote = store.remote else { return "配置待确认" }
        return remote.enabled ? "本机虚拟定位已开启" : "本机虚拟定位已关闭"
    }

    private func addPlace() { editing = Place(name: "", latitude: 0, longitude: 0) }
}

extension AppStore {
    func refreshIfConnected() async { if connection != nil { await refresh() } }
}

