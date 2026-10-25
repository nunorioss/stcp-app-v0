//
//  StopRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 07/06/2026.
//

import SwiftUI

struct StopRow: View {
    @ObservedObject private var favorites = FavoritesStore.shared

    let stop: BusStop
    let showAlias: Bool
    let showLineBadges: Bool
    
    let swipeActions: Bool
    
    @State private var isEditingAlias = false
    @State private var aliasDraft = ""
    
    private let badgesPerRow = 5
    
    init(stop: BusStop, showAlias: Bool = false,
         showLineBadges: Bool = false, swipeActions: Bool = true) {
        self.stop = stop
        self.showAlias = showAlias
        self.showLineBadges = showLineBadges
        self.swipeActions = swipeActions
    }
    
    /// The user's nickname/alias for this stop, if one is set.
    private var alias: String? {
        favorites.getStopAlias(for: stop.id)
    }
    
    /// Adds the favorite / rename swipe actions, unless turned off.
    @ViewBuilder
    private func swipeable(_ row: some View) -> some View {
        if swipeActions {
            row
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    favoriteStopButton
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if favorites.isFavorite(stop: stop.id) {
                        renameStopButton
                    }
                }
        } else {
            row
        }
    }
    
    var body: some View {
         swipeable(HStack {
             VStack(alignment: .leading, spacing: 7) {
                 if showAlias, let alias {
                     Text(alias)
                         .font(.system(.body, design: .rounded))
                     Text(stop.name)
                         .font(.system(.footnote, design: .rounded))
                         .foregroundColor(.secondary)
                 } else {
                     Text(stop.name)
                         .font(.system(.body, design: .rounded))
                 }
                 

                 if showLineBadges {
                     let lines = stop.lines.sorted { $0.shortName < $1.shortName }

                     VStack(alignment: .leading, spacing: 5) {
                         ForEach(Array(stride(from: 0, to: lines.count, by: badgesPerRow)), id: \.self) { start in
                             HStack(spacing: 4) {
                                 ForEach(lines[start..<min(start + badgesPerRow, lines.count)]) { line in
                                     LineBadge(busLine: line, scale: 0.6)
                                 }
                             }
                         }
                     }
                 }

             }

             Spacer(minLength: 20)

             StopBadge(id: stop.id)
         }
         .padding(.vertical, 2))
         .background {
             NavigationLink(value: stop) { EmptyView() }
                 .opacity(0)
         }
         .alert(
            alias == nil ? "Add alias" : "Edit alias",
            isPresented: $isEditingAlias
         ) {
             TextField("e.g. home, work", text: $aliasDraft)
                 .onChange(of: aliasDraft) { _, newValue in
                     if newValue.count > FavoritesStore.maxAliasLength {
                         aliasDraft = String(newValue.prefix(FavoritesStore.maxAliasLength))
                     }
                 }
             
             Button("Save") {
                 favorites.setAlias(aliasDraft, for: stop.id)
             }
             
             Button("Cancel", role: .cancel) { }
             if alias != nil {
                 Button("Remove alias", role: .destructive) {
                     favorites.setAlias(nil, for: stop.id)
                 }
             }
         } message: {
             Text(stop.name).padding(-3)
         }
    }
    
    private var favoriteStopButton: some View {
        let isFavorite = favorites.isFavorite(stop: stop.id)

        return Button {
            withAnimation {
                favorites.toggleFavorite(stop: stop.id)
            }
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "star.slash.fill" : "star.fill")
        }
        .tint(isFavorite ? .gray : .yellow)
    }
    
    private var renameStopButton: some View {
        Button {
            aliasDraft = alias ?? ""
            isEditingAlias = true
        } label: {
            Label(alias == nil ? "Add alias" : "Edit alias", systemImage: "pencil")
        }
        .tint(.blue)
    }
}

#Preview {
    let favorites = FavoritesStore.shared
    favorites.setAlias("to Campanhã", for: "ENX1")
    favorites.setAlias("home", for: "CMP2")
 
    return List {
        StopRow(stop: DataStore.getBusStop(id: "CMP2")!)
        StopRow(stop: DataStore.getBusStop(id: "ENX1")!)
        StopRow(stop: DataStore.getBusStop(id: "JFPD2")!)
    }
}
