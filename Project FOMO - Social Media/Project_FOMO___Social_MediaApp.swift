//
//  Project_FOMO___Social_MediaApp.swift
//  Project FOMO - Social Media
//
//  Created by Mustafa on 11/9/2026.
//

import SwiftUI
import SwiftData

@main
struct Project_FOMO___Social_MediaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
