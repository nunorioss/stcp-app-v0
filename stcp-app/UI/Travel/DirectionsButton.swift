//
//  DirectionsButton.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI

/// Walking directions in another app: Apple Maps, or a choice with Google Maps when it's installed.
struct DirectionsButton: View {
    let from: GeoPoint
    let to: GeoPoint

    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let google = Self.googleMapsURL(from: from, to: to),
               UIApplication.shared.canOpenURL(google) {
                Menu {
                    Button("Apple Maps", systemImage: "map") { open(Self.appleMapsURL(from: from, to: to)) }
                    Button("Google Maps", systemImage: "globe") { openURL(google) }
                } label: {
                    icon
                }
            } else {
                Button {
                    open(Self.appleMapsURL(from: from, to: to))
                } label: {
                    icon
                }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Walking directions")
    }

    private var icon: some View {
        Image(systemName: "arrow.up.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func open(_ url: URL?) {
        if let url { openURL(url) }
    }

    static func appleMapsURL(from: GeoPoint, to: GeoPoint) -> URL? {
        URL(string: "maps://?saddr=\(from.latitude),\(from.longitude)&daddr=\(to.latitude),\(to.longitude)&dirflg=w")
    }

    static func googleMapsURL(from: GeoPoint, to: GeoPoint) -> URL? {
        URL(string: "comgooglemaps://?saddr=\(from.latitude),\(from.longitude)&daddr=\(to.latitude),\(to.longitude)&directionsmode=walking")
    }
}
