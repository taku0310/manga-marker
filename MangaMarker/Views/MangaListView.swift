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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                    openBDService: deps.openBDService,
                    newReleaseChecker: deps.newReleaseChecker
                )
            )
        }
        .overlay(alignment: .top) {
            if viewModel.isCheckingNewReleases {
                NewReleaseCheckingBanner()
            }
        }
        .onAppear { viewModel.reload() }
        .task { await viewModel.autoCheckNewReleases() }
        .refreshable { await viewModel.refreshAllNewReleases() }
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("ライブラリは空です", systemImage: "books.vertical")
        } description: {
            Text("「検索」タブから漫画を追加できます")
        }
    }
}

private struct NewReleaseCheckingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("新刊を確認中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
