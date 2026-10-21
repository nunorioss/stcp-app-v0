//
//  TransitMap+Renderer.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import SwiftUI
import MapKit

extension TransitMapRepresentable.Coordinator {
    private enum ReuseID {
        static let arrow = "arrow"
        static let circle = "circle"
    }
    
    func register(on mapView: MKMapView) {
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: ReuseID.arrow)
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: ReuseID.circle)
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        for view in views where view.annotation is MKUserLocation {
            view.zPriority = .init(rawValue: MKAnnotationViewZPriority.max.rawValue + 1)
        }
    }
    
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        updateArrows(on: mapView)
    }
    
    // overlay renderer
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        switch overlay {
        case let polyline as BorderPolyline:
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBackground
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer

        case let polyline as StyledPolyline:
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(polyline.style.color).withAlphaComponent(polyline.style.opacity)
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer

        default:
            return MKOverlayRenderer(overlay: overlay)
        }
        }

    // annotation renderer
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
                return nil // let MapKit use its default MKUserLocationView, but adjust after
            }
        
        switch annotation {
        case let arrow as ArrowAnnotation:
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: ReuseID.arrow, for: arrow)
            view.image = Self.arrowUIImage
            view.isEnabled = false
            view.zPriority = .min
            view.transform = CGAffineTransform(rotationAngle: arrow.angle)
            return view

        case let stop as StopAnnotation:
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: ReuseID.circle, for: stop)
            view.image = circleUIImage(for: stop.style)
            view.isEnabled = false
            view.zPriority = .min
            return view

        case let bus as BusAnnotation:
            let _bus = bus.bus
            let view = HostingAnnotationView(annotation: bus, reuseIdentifier: nil) {
                BusBadge(color: _bus.line.backgroundColor, bearing: _bus.bearing)
            }
            view.zPriority = .max // always drawn above arrows and stops
            view.canShowCallout = true
            view.detailCalloutAccessoryView = Self.busOverlayUIView(for: bus.bus)
            return view

        default:
            return nil
        }
    }
}
