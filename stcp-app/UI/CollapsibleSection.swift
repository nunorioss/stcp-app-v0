//
//  CollapsibleSection.swift
//  stcp-app
//
//  Created by Nuno Rios on 01/10/2026.
//

import SwiftUI

struct CollapsibleSection<Content: View, Accessory: View>: View {
    let title: String
    let forceExpanded: Bool
    
    let content: Content
    let accessory: Accessory

    private let defaultsKey: String
    @State private var isCollapsed: Bool
    
    let onCollapsedChange: ((Bool) -> Void)?

    init(_ title: String,
         storageKey: String,
         forceExpanded: Bool = false,
         onCollapsedChange: ((Bool) -> Void)? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.forceExpanded = forceExpanded
        self.onCollapsedChange = onCollapsedChange
        self.content = content()
        self.accessory = accessory()

        let key = "collapsed.\(storageKey)"
        self.defaultsKey = key
        _isCollapsed = State(initialValue: UserDefaults.standard.bool(forKey: key))
    }
    
    private func toggle() {
        guard !forceExpanded else {
            return
        }
        withAnimation {
            isCollapsed.toggle()
        }
    }
    
    var body: some View {
        let isExpanded = forceExpanded || !isCollapsed

        Section {
            if isExpanded {
                content
            }
        } header: {
            HStack(spacing: 16) {
                Button(action: toggle) {
                    sectionHeader(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    accessory
                }

                if !forceExpanded {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
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
         forceExpanded: Bool = false,
         onCollapsedChange: ((Bool) -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title, storageKey: storageKey, forceExpanded: forceExpanded,
                  onCollapsedChange: onCollapsedChange,
                  content: content, accessory: { EmptyView() })
    }
}
