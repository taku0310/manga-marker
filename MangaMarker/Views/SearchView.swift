import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject private var deps: AppDependencies
    @State private var navigateManga: Manga?
    @FocusState private var inputFocused: Bool

    @MainActor
    init(deps: AppDependencies) {
        _viewModel = StateObject(wrappedValue: deps.makeSearchViewModel())
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Picker("検索モード", selection: $viewModel.mode) {
                    ForEach(SearchViewModel.SearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                searchField
            }
            .padding(.horizontal)
            .padding(.top, 8)

            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert("エラー", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationDestination(item: $navigateManga) { manga in
            MangaDetailView(deps: deps, manga: manga)
        }
        .onAppear { inputFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($inputFocused)
                .onSubmit { Task { await viewModel.search() } }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    inputFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("入力をクリア")
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
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
                Text("タイトル・著者名・ISBN いずれでも検索できます。")
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

    /// シリーズ名を表示 (巻数は検索結果に表示しない)。
    private var displayTitle: String { book.seriesTitle }

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
