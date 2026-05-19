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
                SearchResultRow(book: book) {
                    if let manga = viewModel.addToLibrary(book) {
                        navigateManga = manga
                    }
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let book: OpenBDParsedBook
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: book.coverImageURL, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(2)
                if let series = book.series, series != book.title {
                    Text(series).font(.caption).foregroundStyle(.secondary)
                }
                Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let v = book.volumeNumber {
                        Label("第\(v)巻", systemImage: "number")
                            .font(.caption2)
                            .labelStyle(.titleOnly)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if let date = book.publishedAt {
                        Text(date, format: .dateTime.year().month())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("ライブラリに追加")
        }
    }
}
