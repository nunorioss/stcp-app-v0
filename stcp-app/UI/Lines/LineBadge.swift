//
//  LineBadge.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import SwiftUI

struct LineBadge: View {
    let shortName: String
    let backgroundColor: Color
    let foregroundColor: Color
    let scale: CGFloat
    
    @ScaledMetric(relativeTo: .headline) private var fontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .headline) private var paddingV: CGFloat = 8
    @ScaledMetric(relativeTo: .headline) private var paddingH: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var cornerRadius: CGFloat = 8
    
    // to make sure that every badge has the same horizontal width
    @ScaledMetric(relativeTo: .headline) private var minWidth: CGFloat = 60
    
    init(busLine: BusLine, scale: CGFloat = 1.0) {
        self.shortName = busLine.shortName
        self.backgroundColor = busLine.backgroundColor
        self.foregroundColor = busLine.foregroundColor
        self.scale = CGFloat(scale)
    }

    init(shortName: String, backgroundColor: Color, foregroundColor: Color, scale: CGFloat = 1.0) {
        self.shortName = shortName
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.scale = CGFloat(scale)
    }
    
    var body: some View {
            Text(shortName)
            .font(.system(size: fontSize * scale, weight: .bold, design: .monospaced))
                .foregroundColor(foregroundColor)
                .frame(minWidth: minWidth * scale)
                .padding(.vertical, paddingV * scale)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius * scale)
                        .fill(backgroundColor)
                )
        }
}

#Preview {
    LineBadge(busLine: DataStore.getBusLine(id: "704")!, scale: 2)
    LineBadge(busLine: DataStore.getBusLine(id: "203")!, scale: 2)
    LineBadge(busLine: DataStore.getBusLine(id: "1M")!, scale: 2)
}
