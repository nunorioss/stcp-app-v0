//
//  LiveToggle.swift
//  stcp-app
//
//  Created by Nuno Rios on 21/10/2026.
//

import SwiftUI

/// Section accessory that filters a list down to entries with live times.
struct LiveToggle: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(isOn ? Color.green : Color.secondary)
                .frame(width: 36, height: 36)
                .background(isOn ? Color.green.opacity(0.15) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
