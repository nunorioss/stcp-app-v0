//
//  BusBadge.swift
//  stcp-app
//
//  Created by Nuno Rios on 23/09/2026.
//

import SwiftUI

struct BusBadge: View {
    var color: Color
    var width: CGFloat = 15

    // Orientation of the bus, in degrees
    var bearing: Double = 0

    var body: some View {
        ZStack {
            Image("BusBody")
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(color)
            Image("BusDetails")
                .resizable()
        }
        .aspectRatio(160.0 / 400.0, contentMode: .fit)
        .frame(width: width)
        .rotationEffect(.degrees(bearing))
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
    }
}
