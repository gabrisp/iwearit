//
//  iWearItApp.swift
//  iWearIt
//
//  Created by Gabrisp on 19/09/2026.
//

import SwiftUI
import CoreData

@main
struct iWearItApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
