//
//  PromptLocalApp.swift
//  PromptLocal
//
//  Created by NimbleEdge Admin on 20/12/25.
//

import SwiftUI

@main
struct PromptLocalApp: App {
    
    var minHeight: CGFloat = 700
    var minWidth: CGFloat = 1250
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: minWidth, minHeight: minHeight)
        }
    }
}
