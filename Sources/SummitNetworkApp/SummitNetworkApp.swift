import SwiftUI

@main
struct SummitNetworkApplication: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
