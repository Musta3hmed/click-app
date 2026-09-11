//
//  ClickApp.swift
//  Click
//
//  App entry point: model container + appearance override.
//

import SwiftUI
import SwiftData

@main
struct ClickApp: App {
    @State private var authSession = AuthSession()

    // The ONE place the appearance override is applied. Sheets get their
    // own host windows, so .preferredColorScheme anywhere lower does not
    // propagate — do not add it elsewhere.
    @AppStorage(DefaultsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue

    let sharedModelContainer: ModelContainer = {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authSession)
                .preferredColorScheme(
                    (AppearanceSetting(rawValue: appearanceRaw) ?? .system).colorScheme
                )
                .task { await authSession.restore() }
        }
        .modelContainer(sharedModelContainer)
    }
}
