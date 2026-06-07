//
//  SwiftChessDemoApp.swift
//  SwiftChessDemo
//
//  Created by Mark Harris on 1/3/26.
//

import SwiftUI

/// Application entry point for the demo.
///
/// This app intentionally keeps the root scene simple so the teaching focus
/// stays on how the three third-party libraries are wired together in the
/// feature views.
@main
struct SwiftChessDemoApp: App {
    /// The single-window scene that hosts the SwiftUI UI.
    var body: some Scene {
        WindowGroup {
            // Start at the configuration screen so learners can see the flow
            // from "choose a side" into the gameplay screen.
            ContentView()
        }
    }
}
