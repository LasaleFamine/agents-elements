import SwiftUI

@main
struct AgentsElementsApp: App {
    @State private var store = ElementsStore()

    init() {
        // CLI verification paths.
        let args = CommandLine.arguments
        if args.contains("--scan-dump") {
            ScannerEngine.dumpAndExit()
        }
        if args.contains("--selftest-mutations") {
            Mutator.runSelftestAndExit()
        }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            MainActor.assumeIsolated { IconRenderer.renderAndExit(to: args[i + 1]) }
        }
        if let i = args.firstIndex(of: "--render-tour"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshotter.renderTour(to: args[i + 1]) }
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            let mode = (i + 2 < args.count) ? args[i + 2] : "overview"
            MainActor.assumeIsolated { Snapshotter.render(to: args[i + 1], mode: mode) }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(store: store)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1140, height: 740)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Agents Elements") { AppChrome.shared.showHelp = true }
            }
            CommandGroup(replacing: .help) {
                Button("Agents Elements Help") { AppChrome.shared.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Label("\(store.liveSessions.count)", systemImage: "square.grid.2x2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
