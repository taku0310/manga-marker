import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel
    @EnvironmentObject private var deps: AppDependencies
    @State private var navigateManga: Manga?

    var body: some View {
        VStack(spacing: 0) {
            Picker("検索モード", selection: $viewModel.mode) {
                ForEach(SearchViewModel.SearchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            content
        }
        .navigationTitle("検索")
        .searchable(text: $viewModel.query, prompt: searchPrompt)
        .onSubmit(of: .search) {
            Task { await viewModel.search() }
        }
        .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationDestination(item: $navigateManga) { manga in
            MangaDetailView(
                viewModel: MangaDetailViewModel(
                    manga: manga,
                    repository: deps.repository,
                    openBDService: deps.openBDService
                )
            )
        }
    }

    private var searchPrompt: String {
        switch viewModel.mode {
        case .auto:  return "タイトル または ISBN を入力"
        case .isbn:  return "ISBN(10桁 または 13桁)"
        case .title: return "タイトル / 著者名"
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView("検索中…")
            Spacer()
        } else if viewModel.results.isEmpty {
            Spacer()
            ContentUnavailableView {
                Label("漫画を検索", systemImage: "magnifyingglass")
            } description: {
                Text("タイトル・著者名・ISBN いずれでも検索できます。\nバーコードを撮影するなら「スキャン」タブが便利です。")
            }
            Spacer()
        } else {
            List(viewModel.results) { book in
                SearchResultRow(book: book, isAdding: viewModel.addingBookId == book.id) {
                    Task {
                        if let manga = await viewModel.addToLibrary(book) {
                            navigateManga = manga
                        }
                    }
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let book: OpenBDParsedBook
    let isAdding: Bool
    let onAdd: () -> Void

    /// シリーズ名を優先表示 (巻数は検索結果に表示しない)。
    private var displayTitle: String { book.series ?? book.title }

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: book.coverImageURL, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle).font(.headline).lineLimit(2)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isAdding {
                ProgressView()
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("全巻をライブラリに追加")
            }
        }
    }
}
