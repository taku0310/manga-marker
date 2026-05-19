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
                        repository: deps.repository
                    )
                )
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                BarcodeScannerView(
                    viewModel: BarcodeScannerViewModel(
                        openBDService: deps.openBDService,
                        repository: deps.repository
                    )
                )
            }
            .tabItem {
                Label("スキャン", systemImage: "barcode.viewfinder")
            }
        }
    }
}
