//
//  SectionHeader.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

struct SectionHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory
    
    // nil when the section can't collapse
    let isExpanded: Bool?
    
    var onToggle: () -> Void = {}

    @Environment(SectionReorderModel.self)
    private var reorder: SectionReorderModel?
    
    @Environment(\.sectionReorderID)
    private var reorderID: String?
    
    @GestureState
    private var isPressing = false

    private var isDragging: Bool {
        reorder?.isDragging == true
    }
    
    // Long press, then drag.
    //Only enabled inside a ReorderableSectionList!
    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($isPressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    reorder?.drag(by: drag?.translation.height ?? 0)
                }
            }
    }

    var body: some View {
        let canReorder = reorder != nil && reorderID != nil

        HStack(spacing: 16) {
            sectionHeader(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                .gesture(reorderGesture, including: canReorder ? .all : .subviews)
                .accessibilityAddTraits(isExpanded == nil ? [] : .isButton)
                .accessibilityAction { onToggle() }

            // while dragging, every section is shown collapsed
            if isExpanded != false && !isDragging {
                accessory
            }

            if let isExpanded {
                SectionChevron(isExpanded: isExpanded && !isDragging)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)
                    .gesture(reorderGesture, including: canReorder ? .all : .subviews)
                    .accessibilityHidden(true)
            }
        }
        // while dragging, the list's overlay draws the headers instead
        .opacity(isDragging ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if let reorderID {
                reorder?.headers[reorderID] = .init(frame: frame, title: title,
                                                    isCollapsible: isExpanded != nil)
            }
        }
        .onChange(of: isPressing) { _, pressing in
            guard let reorderID else {
                // not reorderable
                return
            }
            if pressing {
                reorder?.begin(reorderID)
            } else {
                reorder?.end()
            }
        }
        .onDisappear {
            // removed mid-drag, the press never ends: end the drag (or scrolling stays off)
            if let reorderID, reorder?.dragging == reorderID {
                reorder?.end()
            }
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, isExpanded: Bool?, onToggle: @escaping () -> Void = {}) {
        self.init(title: title, accessory: EmptyView(),
                  isExpanded: isExpanded, onToggle: onToggle)
    }
}

// A collapsed header as drawn while sections are being reordered
struct CollapsedSectionHeader: View {
    let title: String
    let isCollapsible: Bool

    var body: some View {
        HStack(spacing: 16) {
            sectionHeader(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isCollapsible {
                SectionChevron(isExpanded: false)
            }
        }
        .foregroundStyle(.secondary)
    }
}

// the "button" to collapse
struct SectionChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
    }
}

// A header slightly shifted to the left to match the Navigation "Title"
public func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.title3)
        .bold()
        .padding(.leading, -14)
}
