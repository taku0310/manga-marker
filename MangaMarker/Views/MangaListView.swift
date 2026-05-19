import SwiftUI

struct MangaListView: View {
    @StateObject var viewModel: MangaListViewModel
    @EnvironmentObject private var deps: AppDependencies

    var body: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                EmptyLibraryView()
            } else {
                List {
                    ForEach(viewModel.filteredItems) { item in
                        NavigationLink(value: item.manga) {
                            MangaRowView(item: item)
                        }
                    }
                    .onDelete(perform: viewModel.delete)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("ライブラリ")
        .searchable(text: $viewModel.searchText, prompt: "タイトルや著者を検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("完結作品を隠す", isOn: $viewModel.hideCompleted)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .navigationDestination(for: Manga.self) { manga in
            MangaDetailView(
                viewModel: MangaDetailViewModel(
                    manga: manga,
                    repository: deps.repository,
                    openBDService: deps.openBDService
                )
            )
        }
        .onAppear { viewModel.reload() }
        .refreshable {
            viewModel.reload()
            await deps.newReleaseChecker.checkAll()
            viewModel.reload()
        }
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("ライブラリは空です", systemImage: "books.vertical")
        } description: {
            Text("「検索」または「スキャン」タブから漫画を追加できます")
        }
    }
}
