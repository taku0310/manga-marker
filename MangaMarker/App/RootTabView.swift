import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var deps: AppDependencies

    var body: some View {
        TabView {
            NavigationStack {
                MangaListView(deps: deps)
            }
            .tabItem {
                Label("ライブラリ", systemImage: "books.vertical")
            }

            NavigationStack {
                SearchView(deps: deps)
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }
        }
    }
}
