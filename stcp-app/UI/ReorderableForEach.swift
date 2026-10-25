//
//  ReorderableForEach.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI

// List rows the user can reorder by long-pressing one and dragging it.
struct ReorderableForEach<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>

    //the items in their new order, on drop
    let onReorder: ([Item]) -> Void
    let row: (Item) -> Row

    //the rows as shown
    @State private var shown: [Item]

    init(_ items: [Item],
         id: KeyPath<Item, ID>,
         onReorder: @escaping ([Item]) -> Void,
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.id = id
        self.onReorder = onReorder
        self.row = row
        _shown = State(initialValue: items)
    }

    var body: some View {
        ForEach(shown, id: id) { row($0) }
            .onMove { from, to in
                shown.move(fromOffsets: from, toOffset: to)
                onReorder(shown)
            }
            .onChange(of: items.map { $0[keyPath: id] }) {
                shown = items
            }
    }
}
