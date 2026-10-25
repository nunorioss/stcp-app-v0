//
//  SearchField.swift
//  stcp-app
//
//  Created by Nuno Rios on 25/10/2026.
//

import SwiftUI
import UIKit

// The native search bar (UISearchBar), but as a List row instead of in the navigation bar.
// Unlike `.searchable`, it's always there when the screen opens, scrolls away with the
// list, and never collapses the large navigation title.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        NativeSearchBar(text: $text, prompt: prompt)
            .padding(.horizontal, -8)
            .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = prompt
        bar.autocorrectionType = .no
        bar.returnKeyType = .search
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        // e.g. cleared from outside
        if bar.text != text {
            bar.text = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView bar: UISearchBar, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? bar.intrinsicContentSize.width,
               height: bar.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ bar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        //cancel while editing, like the navigation bar's search
        func searchBarTextDidBeginEditing(_ bar: UISearchBar) {
            bar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ bar: UISearchBar) {
            bar.setShowsCancelButton(false, animated: true)
        }

        func searchBarCancelButtonClicked(_ bar: UISearchBar) {
            bar.text = ""
            text = ""
            bar.resignFirstResponder()
        }

        func searchBarSearchButtonClicked(_ bar: UISearchBar) {
            bar.resignFirstResponder()
        }
    }
}
