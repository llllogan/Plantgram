//
//  PlantgramApp.swift
//  Plantgram
//
//  Created by Logan Janssen | Codify on 10/7/2026.
//

import SwiftUI

@main
struct PlantgramApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(sessionStore)
        }
    }
}
