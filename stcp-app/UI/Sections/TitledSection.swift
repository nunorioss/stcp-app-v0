//
//  TitledSection.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

struct TitledSection<Content: View, Accessory: View>: View {
    let title: String
    let content: Content
    let accessory: Accessory

    @Environment(SectionReorderModel.self)
    private var reorder: SectionReorderModel?

    init(_ title: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        Section {
            // while sections are being reordered, just show the headers
            if reorder?.isDragging != true {
                content
            }
        } header: {
            SectionHeader(title: title, accessory: accessory, isExpanded: nil)
        }
    }
}

extension TitledSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, accessory: { EmptyView() })
    }
}
