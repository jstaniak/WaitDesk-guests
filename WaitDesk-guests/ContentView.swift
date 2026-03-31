import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            StatusView()
                .tabItem {
                    Label("Status", systemImage: "house")
                }

            PlaceholderTabView(title: "Tab 2")
                .tabItem {
                    Label("Tab 2", systemImage: "square.grid.2x2")
                }

            PlaceholderTabView(title: "Tab 3")
                .tabItem {
                    Label("Tab 3", systemImage: "bell")
                }

            PlaceholderTabView(title: "Tab 4")
                .tabItem {
                    Label("Tab 4", systemImage: "person")
                }
        }
    }
}

private struct PlaceholderTabView: View {
    let title: String

    var body: some View {
        NavigationStack {
            Text("Empty page")
                .foregroundStyle(.secondary)
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}
