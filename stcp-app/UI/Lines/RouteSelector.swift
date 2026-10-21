//
//  RouteSelector.swift
//  stcp-app
//

import SwiftUI

struct RouteSelector: View {
    let routes: [Route]
    @Binding var selection: Int

    private func title(for route: Route) -> String {
        if let arrow = route.line.heading(route.direction)?.arrow {
            return "\(arrow)  \(route.headsign)"
        }
        return route.headsign
    }

    var body: some View {
        Group {
            if routes.count > 1 {
                Menu {
                    ForEach(routes.indices, id: \.self) { index in
                        // routes are sorted direction 0 first, then 1
                        if index > 0, routes[index].direction != routes[index - 1].direction {
                            Divider()
                        }

                        Button {
                            selection = index
                        } label: {
                            if index == selection {
                                Label(title(for: routes[index]), systemImage: "checkmark")
                            } else {
                                Text(title(for: routes[index]))
                            }
                        }
                    }
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(title(for: routes[min(selection, routes.count - 1)]))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.tint)
                    } label: {
                        Text("Towards")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let route = routes.first {
                LabeledContent {
                    Text(title(for: route))
                        .lineLimit(1)
                } label: {
                    Text("Towards")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

#Preview {
    @Previewable @State var selection = 0
    let routes = DataStore.getBusLine(id: "205")!.routes

    VStack {
        Spacer()
        RouteSelector(routes: routes, selection: $selection)
        Spacer()
    }
}
