//
//  TransitMap+Coordinator.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/09/2026.
//

import SwiftUI
import MapKit

extension TransitMapRepresentable {
    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private(set) var shape: RouteShape?
        
        //MARK: Shape

        /// Returns whether the shape actually changed.
        @discardableResult
        func apply(shape: RouteShape?, on mapView: MKMapView) -> Bool {
            guard shape != self.shape else {
                return false
            }
            self.shape = shape
            
            // draw shape

            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations.filter
                { !($0 is BusAnnotation || $0 is MKUserLocation) }
            )

            if let shape {
                mapView.addOverlays(shape.overlays)
                mapView.addAnnotations(shape.segments.flatMap { segment in
                    segment.stops.map { StopAnnotation(coordinate: $0, style: segment.style) }
                })
            }

            updateArrows(on: mapView)
            return true
        }

        func clearShape(on mapView: MKMapView) {
            apply(shape: nil, on: mapView)
        }

        /// Shows more or fewer arrows depending on how zoomed in the map is.
        func updateArrows(on mapView: MKMapView) {
            guard let shape else {
                return
            }
            
            let shown = mapView.annotations.compactMap { $0 as? ArrowAnnotation }
            let current = shown.map(\.level).max() ?? 0
            let target = Self.arrowLevel(for: mapView)

            if target > current {
                mapView.addAnnotations(
                    shape.arrows.filter { $0.level > current && $0.level <= target }.map(ArrowAnnotation.init)
                )
            } else if target < current {
                mapView.removeAnnotations(shown.filter { $0.level > target })
            }
        }

        private static func arrowLevel(for mapView: MKMapView) -> Int {
            guard mapView.bounds.width > 0 else {
                return 0
            }
            let metersAcross = mapView.visibleMapRect.width
                / MKMapPointsPerMeterAtLatitude(mapView.centerCoordinate.latitude)
            
            switch metersAcross / mapView.bounds.width * 70 {
            case ...250: return 4
            case ...500: return 3
            case ...900: return 2
            case ...1850: return 1
            default: return 0
            }
        }

        // MARK: Buses

        /// Returns whether the set of buses changed.
        @discardableResult
        func apply(buses: [Bus], on mapView: MKMapView) -> Bool {
            var stale = Dictionary(
                mapView.annotations.compactMap { $0 as? BusAnnotation }.map { ($0.bus.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var added: [BusAnnotation] = []

            for bus in buses {
                if let existing = stale.removeValue(forKey: bus.id) {
                    move(existing, to: bus, on: mapView)
                } else {
                    added.append(BusAnnotation(bus: bus))
                }
            }

            mapView.removeAnnotations(Array(stale.values))
            mapView.addAnnotations(added)
            return !(stale.isEmpty && added.isEmpty)
        }

        func clearBuses(on mapView: MKMapView) {
            apply(buses: [], on: mapView)
        }

        private func move(_ annotation: BusAnnotation, to bus: Bus, on mapView: MKMapView) {
            UIView.animate(withDuration: 1) {
                annotation.update(to: bus)
            }

            if let view = mapView.view(for: annotation) as? HostingAnnotationView<BusBadge> {
                view.rootView = BusBadge(color: bus.line.backgroundColor, bearing: bus.bearing)
            }
        }
    }
}
