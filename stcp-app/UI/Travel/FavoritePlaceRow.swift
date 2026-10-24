//
//  FavoritePlaceRow.swift
//  stcp-app
//
//  Created by Nuno Rios on 22/10/2026.
//

import SwiftUI

/// A saved place in the place picker: tap to pick, swipe to unfavorite or edit its alias.
struct FavoritePlaceRow: View {
    let place: FavoritePlace
    let onPick: () -> Void

    @ObservedObject private var favorites = FavoritePlacesStore.shared
    @State private var isEditingAlias = false
    @State private var aliasDraft = ""

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.displayName)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.primary)
                    if place.alias != nil {
                        Text(place.name)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                withAnimation { favorites.remove(place.id) }
            } label: {
                Label("Unfavorite", systemImage: "star.slash.fill")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                aliasDraft = place.alias ?? ""
                isEditingAlias = true
            } label: {
                Label(place.alias == nil ? "Add alias" : "Edit alias", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .alert(place.alias == nil ? "Add alias" : "Edit alias", isPresented: $isEditingAlias) {
            TextField("e.g. home, work", text: $aliasDraft)
                .onChange(of: aliasDraft) { _, newValue in
                    if newValue.count > FavoritesStore.maxAliasLength {
                        aliasDraft = String(newValue.prefix(FavoritesStore.maxAliasLength))
                    }
                }
            Button("Save") { favorites.setAlias(aliasDraft, for: place.id) }
            Button("Cancel", role: .cancel) { }
            if place.alias != nil {
                Button("Remove alias", role: .destructive) { favorites.setAlias(nil, for: place.id) }
            }
        } message: {
            Text(place.name)
        }
    }
}
