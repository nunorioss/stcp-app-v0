//
//  UIUtil.swift
//  stcp-app
//
//  Created by Nuno Rios on 16/09/2026.
//

import SwiftUI

extension Color {
    init(_ rgb: Int) {
        let v = UInt32(rgb)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8)  & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    
    /// Whether the color is (nearly) pure white.
    var isWhite: Bool {
        var red: CGFloat = 0,
            green: CGFloat = 0,
            blue: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)
        return red > 0.98 && green > 0.98 && blue > 0.98
    }

    /// Whether the color is (nearly) pure black.
    var isBlack: Bool {
        var red: CGFloat = 0,
            green: CGFloat = 0,
            blue: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)
        return red < 0.02 && green < 0.02 && blue < 0.02
    }
}
