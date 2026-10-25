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
}
