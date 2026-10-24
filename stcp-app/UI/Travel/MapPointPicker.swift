//
//  MapPointPicker.swift
//  stcp-app
//
//  Created by Nuno Rios on 22/10/2026.
//

import SwiftUI
import MapKit

/// Pan the map under a fixed center pin, then Done picks that spot. The star saves it.
struct MapPointPicker: View {
    /// What a pin at this spot is called, when saved as a favorite.
    let name: (GeoPoint) -> String
    let onPick: (GeoPoint) -> Void

    @ObservedObject private var favorites = FavoritePlacesStore.shared

    /// Where the map opens: the user's location, else São Bento station.
    private static var start: CLLocationCoordinate2D {
        LocationProvider.shared.location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 41.1456, longitude: -8.6108)
    }

    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(center: start, latitudinalMeters: 1500, longitudinalMeters: 1500))
    @State private var center = start

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .onMapCameraChange { context in
            center = context.region.center
        }
        .overlay {
            // tip of the pin on the center
            Image(systemName: "mappin")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.red)
                .offset(y: -18)
                .allowsHitTesting(false)
        }
        .navigationTitle("Choose on Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let point = GeoPoint(latitude: center.latitude, longitude: center.longitude)
                let isFavorite = favorites.isFavorite(at: point)
                Button {
                    favorites.toggleFavorite(name: name(point), location: point)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .primary)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Save to favorites")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onPick(GeoPoint(latitude: center.latitude, longitude: center.longitude))
                }
            }
        }
    }
}
