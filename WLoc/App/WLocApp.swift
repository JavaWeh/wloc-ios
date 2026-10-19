import SwiftUI

@main
@MainActor
struct WLocApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}

