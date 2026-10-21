//
//  SegmentStyle.swift
//  stcp-app
//
//  Created by Nuno Rios on 24/09/2026.
//

import SwiftUI

struct SegmentStyle: Hashable {
    let color: Color
    let opacity: Double // 0..1
    var dashed = false

    /// Dotted gray line for walking legs.
    static let walking = SegmentStyle(color: Color(.systemGray), opacity: 1, dashed: true)
    
    static func solid(_ color: Color) -> SegmentStyle {
        SegmentStyle(color: color, opacity: 1)
    }
    
    static func dimmed(_ color: Color, opacity: Double = 0.35) -> SegmentStyle {
        SegmentStyle(color: color, opacity: opacity)
    }
}
