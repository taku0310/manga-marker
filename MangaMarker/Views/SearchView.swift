import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel
    @EnvironmentObject private var deps: AppDependencies
    @State private var navigateManga: Manga?

    var body: some View {
        Group {
            if viewModel.isSearching {
                ProgressView("検索中…")
            } else if viewModel.results.isEmpty {
                ContentUnavailableView {
                    Label("漫画を検索", systemImage: "magnifyingglass")
                } description: {
                    Text("ISBN(10桁または13桁)を入力してください。\nタイトル検索は将来対応します。")
                }
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
        .navigationTitle("検索")
        .searchable(text: $viewModel.query, prompt: "ISBNを入力")
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
}

private struct SearchResultRow: View {
    let book: OpenBDParsedBook
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: book.coverImageURL, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(2)
                if let series = book.series { Text(series).font(.caption).foregroundStyle(.secondary) }
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                if let v = book.volumeNumber { Text("第\(v)巻").font(.caption) }
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }
}
