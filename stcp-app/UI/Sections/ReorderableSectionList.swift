//
//  ReorderableSectionList.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

extension EnvironmentValues {
    // the ID of the ReorderableSectionList item a section belongs to
    @Entry var sectionReorderID: String? = nil
}

// A List whose sections can be reordered by long-pressing their header and dragging.
struct ReorderableSectionList<Item, Content: View>: View
where Item: RawRepresentable & Hashable, Item.RawValue == String {
    // every section, in its default order
    let items: [Item]
    
    // sections with nothing to show
    //they only appear while reordering, so they can still be put in place
    let hidden: Set<Item>
    
    let content: (Item) -> Content

    // ids in the user's order (saved by the model on drop); can include hidden sections
    @AppStorage private var savedOrder: String
    @State private var model: SectionReorderModel

    init(_ items: [Item],
         hidden: Set<Item> = [],
         orderKey: String,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.hidden = hidden
        self.content = content
        _savedOrder = AppStorage(wrappedValue: "", orderKey)
        _model = State(initialValue: SectionReorderModel(orderKey: orderKey))
    }

    // "items" in the saved order;
    //ones never ordered keep their default place (the sort is stable)
    private var orderedItems: [Item] {
        let rank = Dictionary(SectionReorderModel.ids(in: savedOrder).enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        return items.sorted { rank[$0.rawValue, default: .max] < rank[$1.rawValue, default: .max] }
    }

    var body: some View {
        let orderedItems = orderedItems

        List {
            ForEach(orderedItems.filter { model.isDragging || !hidden.contains($0) }, id: \.self) { item in
                content(item)
                    .environment(\.sectionReorderID, item.rawValue)
            }
        }
        .environment(model)
        // no scrolling or pull-to-refresh while a header is being dragged
        .scrollDisabled(model.isDragging)
        .overlay { SectionReorderOverlay(model: model) }
        .sensoryFeedback(.impact, trigger: model.dragging) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: model.target)
        .onChange(of: orderedItems.map(\.rawValue), initial: true) { _, ids in
            model.itemIDs = ids
        }
    }
}

private struct SectionReorderOverlay: View { // the headers while dragging
    let model: SectionReorderModel

    var body: some View {
        GeometryReader { proxy in
            // only read while dragging
            let slots = model.isDragging ? model.slots : []
            
            if let dragging = model.dragging, slots.count == model.order.count {
                let origin = proxy.frame(in: .global).origin
                
                ForEach(Array(model.droppedOrder.enumerated()), id: \.element) { index, id in
                    let isDragged = id == dragging
                    let slot = slots[index]
                    let header = model.headers[id]
                    
                    CollapsedSectionHeader(title: header?.title ?? "",
                                           isCollapsible: header?.isCollapsible ?? false)
                        .frame(width: slot.width, height: slot.height)
                        .scaleEffect(isDragged ? 1.1 : 1, anchor: .leading)
                        .shadow(color: .black.opacity(isDragged ? 0.18 : 0), radius: 10, y: 6)
                        .position(x: slot.midX - origin.x,
                                  y: (isDragged ? model.startFrame.midY + model.translation : slot.midY) - origin.y)
                        // the others slide to their new slot; the dragged one stays on the finger
                        .animation(isDragged ? nil : .snappy, value: model.target)
                        .zIndex(isDragged ? 1 : 0)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// The drag state of one ReorderableSectionList,
//shared with its sections' headers.
@Observable
final class SectionReorderModel {
    struct Header {
        var frame: CGRect   // global
        var title: String
        var isCollapsible: Bool
    }

    var headers: [String: Header] = [:]
    
    // current order of visible items (IDs)
    var itemIDs: [String] = []

    private(set) var dragging: String?          // ID of item being dragged
    private(set) var startFrame: CGRect = .zero // the dragged header's frame, when the drag began
    private(set) var translation: CGFloat = 0   // how far the finger has moved since
    private(set) var order: [String] = []       // itemIDs when the drag began
    private(set) var target = 0                 // the slot the dragged item would get if dropped now

    private let orderKey: String

    init(orderKey: String) {
        self.orderKey = orderKey
    }

    var isDragging: Bool {
        dragging != nil
    }

    // where the (collapsed) headers sit,
    // top to bottom: the slots items drop into
    var slots: [CGRect] {
        order.compactMap { headers[$0]?.frame }
    }

    // "order" with the dragged item moved to "target"
    var droppedOrder: [String] {
        guard let dragging,
              let from = order.firstIndex(of: dragging) else {
            return order
        }
        
        var result = order
        result.remove(at: from)
        result.insert(dragging, at: min(target, result.count))
        return result
    }

    func begin(_ id: String) {
        // a second press mid-drag, or a header that hasn't reported its frame yet
        guard !isDragging, let frame = headers[id]?.frame else {
            return
        }
        startFrame = frame
        translation = 0
        order = itemIDs
        target = order.firstIndex(of: id) ?? 0
        
        withAnimation(.snappy) {
            dragging = id
        }
    }

    //follows the finger, and points the drop at the slot nearest it
    func drag(by translation: CGFloat) {
        self.translation = translation
        
        let slots = slots
        guard slots.count == order.count else {
            return
        }
    
        let fingerY = startFrame.midY + translation
        let nearest = slots.indices.min {
            abs(slots[$0].midY - fingerY) < abs(slots[$1].midY - fingerY)
        } ?? target
        
        if nearest != target {
            target = nearest
        }
    }

    func end() {
        guard isDragging else {
            return
        }
        let dropped = droppedOrder
        
        withAnimation(.snappy) {
            save(dropped)
            dragging = nil
            translation = 0
        }
    }

    // Saves the shown items' order, while hidden ones keep theirs.
    private func save(_ shown: [String]) {
        let saved = Self.ids(in: UserDefaults.standard.string(forKey: orderKey) ?? "")
        let shownSet = Set(shown)
        let order = shown + saved.filter {
            !shownSet.contains($0)
        }
        UserDefaults.standard.set(order.joined(separator: ","), forKey: orderKey)
    }

    // the saved order is the ids joined with commas (so ids mustn't contain one)
    static func ids(in savedOrder: String) -> [String] {
        savedOrder.split(separator: ",").map(String.init)
    }
}
