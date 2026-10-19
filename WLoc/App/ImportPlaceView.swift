import SwiftUI
import MapKit

struct ImportPlaceView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft = MapImportDraft()
    @State private var error: String?
    @State private var parsing = false
    @State private var pickingMap = false
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 95)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("粘贴苹果地图、高德或 Google Maps 分享链接")
                    Button {
                        parseTask = Task { await parse() }
                    } label: {
                        HStack { Label("解析链接 / 坐标", systemImage: "link"); Spacer(); if parsing { ProgressView() } }
                    }.disabled(parsing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { pickingMap = true } label: { Label("在 App 地图中搜索和选点", systemImage: "map") }.disabled(parsing)
                } header: { Text("复制地图链接后在这里粘贴") } footer: {
                    Text("支持地图分享文字、长链接、部分短链接和“纬度,经度”。带坐标的链接本机解析；短链需联网向对应地图服务展开，不使用自建后台。")
                }
                Section("确认地点") {
                    TextField("地点名称（例如：公司）", text: $draft.name)
                    field("纬度", text: $draft.latitude)
                    field("经度", text: $draft.longitude)
                    Picker("原始坐标系", selection: $draft.system) {
                        ForEach(CoordinateSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("来源：\(draft.source)").font(.caption).foregroundStyle(.secondary)
                    if let warning = draft.warning { Text(warning).font(.subheadline).foregroundStyle(.orange) }
                    if let coordinate = normalized {
                        Text("保存为 WGS-84：\(coordinate.text)").font(.caption.monospacedDigit())
                        CoordinatePreview(coordinate: coordinate).frame(height: 190)
                    }
                }.disabled(parsing)
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("导入 / 标记位置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("收藏") { save() }.disabled(parsing) }
            }
            .sheet(isPresented: $pickingMap) {
                NativeMapPicker(initial: normalized, initialQuery: MapLinkParser.firstURL(in: text) == nil ? text : "") { parsed in populate(parsed) }
            }
            .onDisappear { parseTask?.cancel() }
            .onChange(of: text) { _ in
                parseTask?.cancel()
                draft.reset()
                parsing = false
                error = nil
            }
        }
    }

    private var normalized: Coordinate? {
        draft.normalized
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack { Text(title); TextField(title, text: text).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).autocorrectionDisabled() }
    }
    private func populate(_ parsed: ParsedLocation) {
        draft.select(parsed)
        error = nil
    }
    private func parse() async {
        guard !parsing else { return }
        let input = text
        let token = draft.reset()
        parsing = true
        error = nil
        defer { if draft.revision == token { parsing = false } }
        do {
            let result = try await MapLinkResolver().resolve(input)
            try Task.checkCancellation()
            if text == input, draft.accept(result, for: token) { error = nil }
        } catch is CancellationError { }
        catch let known as WLocError { if draft.revision == token { self.error = known.localizedDescription } }
        catch { if draft.revision == token { self.error = "短链展开失败，请检查网络、复制完整链接，或使用 App 地图选点。" } }
    }
    private func save() {
        guard let coordinate = normalized else { error = WLocError.invalidCoordinate.localizedDescription; return }
        let place = Place(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), latitude: coordinate.latitude, longitude: coordinate.longitude)
        do { try place.validate() } catch { self.error = error.localizedDescription; return }
        if store.save(place) { dismiss() } else { error = "本机收藏保存失败，请检查储存空间。" }
    }
}

private struct PreviewPin: Identifiable { let id = 0; let coordinate: CLLocationCoordinate2D }

struct CoordinatePreview: View {
    let coordinate: Coordinate
    var body: some View {
        // MapKit's CLLocationCoordinate2D contract is WGS-84, unlike a web-map tile projection.
        let location = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Map(coordinateRegion: .constant(MKCoordinateRegion(center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))), annotationItems: [PreviewPin(coordinate: location)]) {
            MapMarker(coordinate: $0.coordinate, tint: .red)
        }.allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct NativeMapPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion
    @State private var query: String
    @State private var candidates: [MKMapItem] = []
    @State private var selectedName = ""
    @State private var error: String?
    @State private var searching = false
    @State private var activeSearch: MKLocalSearch?
    let onPick: (ParsedLocation) -> Void

    init(initial: Coordinate?, initialQuery: String, onPick: @escaping (ParsedLocation) -> Void) {
        let coordinate = initial ?? Coordinate(latitude: 39.9042, longitude: 116.4074)
        _region = State(initialValue: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        _query = State(initialValue: initialQuery)
        self.onPick = onPick
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("输入地址或地点名称", text: $query).textFieldStyle(.roundedBorder).onSubmit { Task { await search() } }
                    Button("搜索") { Task { await search() } }.disabled(searching || query.isEmpty)
                    if searching { ProgressView() }
                }.padding()
                if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                if !candidates.isEmpty {
                    List(Array(candidates.enumerated()), id: \.offset) { _, item in
                        Button {
                            region.center = item.placemark.coordinate
                            region.span = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                            selectedName = item.name ?? ""
                            candidates = []
                        } label: {
                            VStack(alignment: .leading) { Text(item.name ?? "地点"); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.frame(maxHeight: 200)
                }
                Map(coordinateRegion: $region)
                    .overlay { Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(.red).allowsHitTesting(false) }
                Text("拖动地图，将十字准星放在目标位置，再确认坐标系。").font(.caption).foregroundStyle(.secondary).padding(8)
                Button("使用地图中心位置") {
                    let coordinate = Coordinate(latitude: region.center.latitude, longitude: region.center.longitude)
                    onPick(ParsedLocation(coordinate: coordinate, name: selectedName,
                                          system: .wgs84, source: "App MapKit 选点（WGS-84）", warning: nil))
                    dismiss()
                }.buttonStyle(.borderedProminent).padding().disabled(searching)
            }
            .navigationTitle("地图选点").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onDisappear { activeSearch?.cancel() }
            .onChange(of: query) { _ in
                activeSearch?.cancel()
                candidates = []
                error = nil
            }
        }
    }
    private func search() async {
        guard !searching else { return }
        searching = true
        error = nil
        defer { searching = false }
        let request = MKLocalSearch.Request()
        let input = query
        request.naturalLanguageQuery = input
        request.region = region
        let search = MKLocalSearch(request: request)
        activeSearch = search
        do {
            let response = try await search.start()
            guard query == input, !Task.isCancelled else { return }
            candidates = Array(response.mapItems.prefix(8))
            if candidates.isEmpty { error = "未找到地点，请更换名称或直接拖动地图。" }
        } catch { if query == input { self.error = "地图搜索失败，请检查网络后重试。" } }
    }
}
