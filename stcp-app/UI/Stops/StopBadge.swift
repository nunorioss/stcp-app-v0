//
//  StopBadge.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import SwiftUI

struct StopBadge: View {
    let id: String
    let scale: CGFloat

    @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var paddingV: CGFloat = 7
    @ScaledMetric(relativeTo: .caption) private var paddingH: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var cornerRadius: CGFloat = 8
    
    @ScaledMetric(relativeTo: .caption) private var minWidth: CGFloat = 43
    
    init(id: String, scale: CGFloat = 1.0) {
        self.id = id
        self.scale = scale
    }

    var body: some View {
        Text(id)
            .font(.system(size: fontSize * scale, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(minWidth: minWidth * scale)
            .padding(.vertical, paddingV * scale)
            .padding(.horizontal, paddingH * scale)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.75)
            )
    }
}

#Preview {
    StopBadge(id: "JFPD2", scale: 2)
    StopBadge(id: "ENX1", scale: 2)
    StopBadge(id: "ART6", scale: 2)
}
