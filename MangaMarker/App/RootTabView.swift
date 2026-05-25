import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var deps: AppDependencies

    var body: some View {
        TabView {
            NavigationStack {
                MangaListView(
                    viewModel: MangaListViewModel(repository: deps.repository)
                )
            }
            .tabItem {
                Label("ライブラリ", systemImage: "books.vertical")
            }

            NavigationStack {
                SearchView(
                    viewModel: SearchViewModel(
                        openBDService: deps.openBDService,
                        bookSearchService: deps.bookSearchService,
                        repository: deps.repository
                    )
                )
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }
        }
    }
}
