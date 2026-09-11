//
//  Project_FOMO___Social_MediaApp.swift
//  Click
//
//  The Xcode target is still named "Project FOMO - Social Media", so the
//  @main type keeps its mangled template name. The product is called Click.
//

import SwiftUI
import SwiftData

@main
struct Project_FOMO___Social_MediaApp: App {
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
        }
        .modelContainer(sharedModelContainer)
    }
}
