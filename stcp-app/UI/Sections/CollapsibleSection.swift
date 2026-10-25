//
//  CollapsibleSection.swift
//  stcp-app
//
//  Created by Nuno Rios on 01/10/2026.
//

import SwiftUI

struct CollapsibleSection<Content: View, Accessory: View>: View {
    let title: String
    let content: Content
    let accessory: Accessory

    private let defaultsKey: String
    @State private var isCollapsed: Bool

    let onCollapsedChange: ((Bool) -> Void)?

    @Environment(SectionReorderModel.self)
    private var reorder: SectionReorderModel?

    init(_ title: String,
         storageKey: String,
         onCollapsedChange: ((Bool) -> Void)? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.onCollapsedChange = onCollapsedChange
        self.content = content()
        self.accessory = accessory()

        let key = "collapsed.\(storageKey)"
        self.defaultsKey = key
        _isCollapsed = State(initialValue: UserDefaults.standard.bool(forKey: key))
    }

    private func toggle() {
        withAnimation {
            isCollapsed.toggle()
        }
    }

    var body: some View {
        Section {
            // while sections are being reordered, just show the headers
            if !isCollapsed && reorder?.isDragging != true {
                content
            }
        } header: {
            SectionHeader(title: title, accessory: accessory,
                          isExpanded: !isCollapsed, onToggle: toggle)
        }
        .onChange(of: isCollapsed) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
        .onChange(of: isCollapsed, initial: true) { _, newValue in
            onCollapsedChange?(newValue)
        }
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(_ title: String,
         storageKey: String,
         onCollapsedChange: ((Bool) -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title, storageKey: storageKey, onCollapsedChange: onCollapsedChange,
                  content: content, accessory: { EmptyView() })
    }
}
