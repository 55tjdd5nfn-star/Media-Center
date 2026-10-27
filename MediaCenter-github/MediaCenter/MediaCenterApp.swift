import SwiftUI

@main
struct MediaCenterApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)

                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
