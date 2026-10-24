//
//  TransitMap+Static.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import SwiftUI

extension TransitMapRepresentable.Coordinator {
    private struct CircleKey: Hashable {
        let style: SegmentStyle
        let isEndpoint: Bool
    }

    private static var circleImageCache: [CircleKey: UIImage] = [:]
    
    // UIImage for "arrow" direction markers
    // static, independent of the route
    static let arrowUIImage = triangleUIImage(color: UIColor.white.withAlphaComponent(0.8))

    // standalone arrows marking walking legs
    static let walkingArrowUIImage = triangleUIImage(color: UIColor(SegmentStyle.walking.color))

    private static func triangleUIImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 6)
        
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.close()
            color.setFill()
            path.fill()
        }
    }

    // UIImage for circle stop annotations
    // dependent on the color of the segment
    func circleUIImage(for style: SegmentStyle, isEndpoint: Bool = false) -> UIImage {
        let key = CircleKey(style: style, isEndpoint: isEndpoint)
        if let cached = Self.circleImageCache[key] {
            return cached
        }

        let diameter: CGFloat = isEndpoint ? 8 : 5
        let lineWidth: CGFloat = isEndpoint ? 1.5 : 1
        let side = diameter + lineWidth * 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let path = UIBezierPath(ovalIn: CGRect(x: lineWidth, y: lineWidth, width: diameter, height: diameter))
            UIColor.white.setFill()
            path.fill()
            UIColor(style.color).withAlphaComponent(style.opacity).setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }

        Self.circleImageCache[key] = image
        return image
    }
    
    static func busOverlayUIView(for bus: Bus) -> UIView {
        let controller = UIHostingController(rootView: BusOverlay(bus: bus))
        controller.sizingOptions = .intrinsicContentSize
        controller.view.backgroundColor = .clear
        return controller.view
    }
}
