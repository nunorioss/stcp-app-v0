//
//  ContentView.swift
//  stcp-app
//
//  Created by Nuno Rios on 06/06/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        let x = LocationProvider.shared.requestPermission()

        TabView {
            NavigationStack {
                LineList()
            }
            .tabItem {
                Label("Lines", systemImage: "bus")
            }
            
            NavigationStack {
                StopList()
            }
            .tabItem {
                Label("Stops", systemImage: "mappin.and.ellipse")
            }
        }
    }
}

#Preview {
    ContentView()
}
