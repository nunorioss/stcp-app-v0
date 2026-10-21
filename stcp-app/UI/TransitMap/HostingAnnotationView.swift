//
//  HostingAnnotationView.swift
//  stcp-app
//
//  Created by Nuno Rios on 20/09/2026.
//

import MapKit
import SwiftUI

/// Each instance carries a `UIHostingController`, so this is reserved for
/// the handful of live buses on screen. Arrows and stop dots are plain
/// `MKAnnotationView`s backed by a cached `UIImage` instead.
final class HostingAnnotationView<Content: View>: MKAnnotationView {
    private let hosting: UIHostingController<Content>
 
    /// Re-renders in place, so an existing annotation view can
    /// follow its bus instead of being torn down and rebuilt on every refresh.
    var rootView: Content {
        get { hosting.rootView }
        set {
            hosting.rootView = newValue
            resize()
        }
    }
 
    init(annotation: MKAnnotation?, reuseIdentifier: String?, @ViewBuilder content: () -> Content) {
        hosting = UIHostingController(rootView: content())
        hosting.view.backgroundColor = .clear
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
 
        backgroundColor = .clear
        canShowCallout = false
 
        addSubview(hosting.view)
        resize()
        centerOffset = .zero
    }
 
    private func resize() {
        let size = hosting.sizeThatFits(in: CGSize(width: 200, height: 200))
        hosting.view.frame = CGRect(origin: .zero, size: size)
        bounds = CGRect(origin: .zero, size: size)
    }
 
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
