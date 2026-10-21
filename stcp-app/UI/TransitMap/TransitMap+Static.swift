//
//  TransitMap+Static.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import SwiftUI

extension TransitMapRepresentable.Coordinator {
    private static var circleImageCache: [SegmentStyle: UIImage] = [:]
    
    // UIImage for "arrow" direction markers
    // static, independent of the route
    static let arrowUIImage: UIImage = {
        let size = CGSize(width: 4, height: 6)
        
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.close()
            UIColor.white.withAlphaComponent(0.8).setFill()
            path.fill()
        }
    }()

    // UIImage for circle stop annotations
    // dependent on the color of the segment
    func circleUIImage(for style: SegmentStyle) -> UIImage {
        if let cached = Self.circleImageCache[style] {
            return cached
        }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6)).image { _ in
            let path = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 4, height: 4))
            UIColor.white.setFill()
            path.fill()
            UIColor(style.color).withAlphaComponent(style.opacity).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        Self.circleImageCache[style] = image
        return image
    }
    
    static func busOverlayUIView(for bus: Bus) -> UIView {
        let controller = UIHostingController(rootView: BusOverlay(bus: bus))
        controller.sizingOptions = .intrinsicContentSize
        controller.view.backgroundColor = .clear
        return controller.view
    }
}
