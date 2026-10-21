//
//  TransitMapRepresentable.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import MapKit
import SwiftUI

struct TransitMapRepresentable: UIViewRepresentable {
    var shape: RouteShape? = nil
    var buses: [Bus] = []
    
    /// Framed together with the buses when there's no shape; typically the stop.
    var focus: CLLocationCoordinate2D? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = true
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 1500
        )

        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.showsTraffic = false
        config.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .publicTransport, .hospital, .school, .university, .airport, .stadium
        ])
        
        mapView.preferredConfiguration = config

        context.coordinator.register(on: mapView)
        apply(to: mapView, with: context.coordinator, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        apply(to: mapView, with: context.coordinator, animated: true)
    }

    private func apply(to mapView: MKMapView,
                       with coordinator: Coordinator,
                       animated: Bool = true) {
        let shapeChanged = coordinator.apply(shape: shape, on: mapView)
        let busesChanged = coordinator.apply(buses: buses, on: mapView)

        // only move the camera when what it frames changed
        let rect: MKMapRect
        if let shapeRect = shape?.framingRect {
            guard shapeChanged else {
                return
            }
            rect = shapeRect
        } else if let focus, shapeChanged || busesChanged {
            rect = buses.isEmpty
                ? MKMapRect(center: focus, radius: 3000)
                : MKMapRect(fitting: [focus] + buses.map(\.location.coordinate))
        } else {
            return
        }

        let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
    }
}

extension MKMapRect {
    init(center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        let point = MKMapPoint(center)
        let r = radius * MKMapPointsPerMeterAtLatitude(center.latitude)
        self.init(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)
    }

    init(fitting coordinates: [CLLocationCoordinate2D]) {
        self = coordinates
            .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
            .reduce(.null) { $0.union($1) }
    }
}
