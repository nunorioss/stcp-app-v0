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
    
    static func solid(_ color: Color) -> SegmentStyle {
        SegmentStyle(color: color, opacity: 1)
    }
    
    static func dimmed(_ color: Color, opacity: Double = 0.35) -> SegmentStyle {
        SegmentStyle(color: color, opacity: opacity)
    }
}
