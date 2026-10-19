import SwiftUI

struct PlaceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let original: Place
    @State private var name: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var accuracy: String
    @State private var error: String?

    init(place: Place) {
        original = place
        _name = State(initialValue: place.name)
        _latitude = State(initialValue: String(place.latitude))
        _longitude = State(initialValue: String(place.longitude))
        _accuracy = State(initialValue: String(place.horizontalAccuracy))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("地点名称") {
                    TextField("例如：家、公司、常去的地点", text: $name)
                }
                Section {
                    coordinateField("纬度", placeholder: "-90 ～ 90", value: $latitude)
                    coordinateField("经度", placeholder: "-180 ～ 180", value: $longitude)
                } header: { Text("WGS-84 坐标") } footer: {
                    Text("经纬度请勿填反。高德、腾讯地图通常使用 GCJ-02，百度地图使用 BD-09，不能直接当作 WGS-84 输入。可在首页收藏现有服务的正确坐标。负数可切换数字符号键盘输入或直接粘贴。")
                }
                Section {
                    coordinateField("水平精度（米）", placeholder: "39", value: $accuracy)
                } footer: { Text("只提交经纬度和水平精度，保留服务现有的海拔等其他配置。保存地点仅存到手机，返回首页点选后才提交到服务。") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(original.name.isEmpty ? "添加地点" : "编辑地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func coordinateField(_ title: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            TextField(placeholder, text: value).keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }

    private func save() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lng = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let horizontalAccuracy = Double(accuracy.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "请输入有效数字，小数点请使用英文句点。"; return
        }
        var place = original
        place.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        place.latitude = lat
        place.longitude = lng
        place.horizontalAccuracy = horizontalAccuracy
        do { try place.validate() } catch { self.error = error.localizedDescription; return }
        if store.save(place) { dismiss() }
        else { error = "无法保存地点，请检查设备储存空间。" }
    }
}

