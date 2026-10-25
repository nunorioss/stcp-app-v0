//
//  LineList.swift
//  stcp-app
//
//  Created by Nuno Rios on 19/09/2026.
//

import SwiftUI

struct LineList: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    
    @State private var searchText = ""
    
    // Lines sorted by ID
    private static let allLines: [BusLine] = DataStore.getBusLines().sorted {
        $0.id.localizedStandardCompare($1.id) == .orderedAscending
    }
    
    // Dawn line IDs end with "M"
    private static let dawnLines: [BusLine] = allLines
        .filter { $0.id.hasSuffix("M") && !isSpecial($0) }
    private static let regularLines: [BusLine] = allLines
        .filter { !$0.id.hasSuffix("M") && !isSpecial($0) }
    
    // Special lines contain "special"/"especial"
    nonisolated private static func isSpecial(_ line: BusLine) -> Bool {
        line.longName.localizedStandardContains("special")
    }
    private static let specialLines: [BusLine] = allLines.filter(isSpecial)
    
    // Case- and accent-insensitive match on the short or long name
    private func filtered(_ lines: [BusLine], by query: String) -> [BusLine] {
        guard !query.isEmpty else {
            return lines
        }
 
        return lines.filter {
            $0.shortName.localizedStandardContains(query)
            || $0.longName.localizedStandardContains(query)
        }
    }
    
    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let isSearching = !query.isEmpty
                
        // only computed while searching
        let results = isSearching ? filtered(Self.allLines, by: query) : []
        
        List {
            if isSearching {
                ForEach(results, id: \.id) { LineRow(line: $0) }
                
            } else {
                let favoriteLines = favorites.getFavoriteLines
                
                if !favoriteLines.isEmpty {
                    CollapsibleSection("Favorites", storageKey: "lines.favorites") {
                        ReorderableForEach(favoriteLines, id: \.id,
                                           onReorder: { favorites.reorderLines($0.map(\.id)) }) {
                            LineRow(line: $0)
                        }
                    }
                }
                
                // Show "M" lines on top during dawn
                if DateUtil.isDawnTime() {
                    CollapsibleSection("Dawn lines", storageKey: "lines.dawn") {
                        ForEach(Self.dawnLines, id: \.id) { LineRow(line: $0) }
                    }
                    CollapsibleSection("Daytime lines", storageKey: "lines.regular") {
                        ForEach(Self.regularLines, id: \.id) { LineRow(line: $0) }
                    }
                } else {
                    CollapsibleSection("Daytime lines", storageKey: "lines.regular") {
                        ForEach(Self.regularLines, id: \.id) { LineRow(line: $0) }
                    }
                    CollapsibleSection("Dawn lines", storageKey: "lines.dawn") {
                        ForEach(Self.dawnLines, id: \.id) { LineRow(line: $0) }
                    }
                }
                
                if !Self.specialLines.isEmpty {
                    CollapsibleSection("Special lines", storageKey: "lines.special") {
                        ForEach(Self.specialLines, id: \.id) { LineRow(line: $0) }
                    }
                }
            }
        }
        // Clicking a line row leads to its line view
        .navigationDestination(for: BusLine.self) {
            LineView(line: $0)
        }
        .overlay {
            if isSearching, results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search lines")
        .autocorrectionDisabled()
        .navigationTitle("Lines")
    }
}

#Preview {
    NavigationStack {
        LineList()
    }
}
