//
//  LineRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import SwiftUI

struct LineRow: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    
    let line: BusLine
    
    /// Splits the BusLine's long name into two parts: its main name and an
    /// optional section with more details about the route. The details start
    /// at the word "via", with or without parentheses.
    private var name: (main: String, via: String?) {
        let name = line.longName
        
        guard let range = name.range(of: #"\s*\(via\b|\s+via\b"#, options: .regularExpression) else {
            return (name, nil)
        }
        
        let main = String(name[..<range.lowerBound])
        let detail = name[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        
        return (main, "via " + detail)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.main)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)

                if let via = name.via {
                    Text(via)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 20)

            LineBadge(busLine: line)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            favoriteLineButton
        }
        .background {
            NavigationLink(value: line) { EmptyView() }
                .opacity(0)
        }
    }
    
    private var favoriteLineButton: some View {
        let isFavorite = favorites.isFavorite(line: line.id)

        return Button {
            withAnimation {
                favorites.toggleFavorite(line: line.id)
            }
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "star.slash.fill" : "star.fill")
        }
        .tint(isFavorite ? .gray : .yellow)
    }
}

#Preview {
    List {
        LineRow(line: DataStore.getBusLine(id: "704")!)
        LineRow(line: DataStore.getBusLine(id: "203")!)
        LineRow(line: DataStore.getBusLine(id: "1M")!)
    }
}
