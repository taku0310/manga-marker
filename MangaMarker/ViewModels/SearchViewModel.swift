import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    enum SearchMode: String, CaseIterable, Identifiable {
        case auto = "自動"
        case isbn = "ISBN"
        case title = "タイトル"
        var id: String { rawValue }
    }

    @Published var query: String = ""
    @Published var mode: SearchMode = .auto
    @Published private(set) var results: [OpenBDParsedBook] = []
    @Published private(set) var isSearching: Bool = false
    @Published var errorMessage: String?

    private let openBDService: OpenBDService
    private let bookSearchService: BookSearchService
    private let repository: MangaRepository

    init(openBDService: OpenBDService,
         bookSearchService: BookSearchService,
         repository: MangaRepository) {
        self.openBDService = openBDService
        self.bookSearchService = bookSearchService
        self.repository = repository
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        switch resolvedMode(for: trimmed) {
        case .isbn:
            await searchByISBN(trimmed)
        case .title:
            await searchByTitle(trimmed)
        case .auto:
            results = []
        }
    }

    private func resolvedMode(for trimmed: String) -> SearchMode {
        if mode != .auto { return mode }
        let digitsOnlyish = trimmed.allSatisfy { $0.isNumber || $0 == "-" || $0 == " " }
        let digits = trimmed.filter(\.isNumber)
        if digitsOnlyish && (digits.count == 10 || digits.count == 13) {
            return .isbn
        }
        return .title
    }

    // MARK: - Search implementations

    private func searchByISBN(_ input: String) async {
        let digits = input.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 13 else {
            errorMessage = "ISBN は 10 桁または 13 桁の数字で入力してください"
            results = []
            return
        }
        do {
            let book = try await openBDService.fetch(isbn: digits)
            results = [book]
        } catch {
            // OpenBD で見つからない場合は書誌検索サービス (楽天Kobo→Google) にフォールバック
            do {
                results = try await bookSearchService.searchByTitle("isbn:\(digits)")
                if results.isEmpty {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    private func searchByTitle(_ input: String) async {
        do {
            results = try await bookSearchService.searchByTitle(input)
            if results.isEmpty {
                errorMessage = "該当する漫画が見つかりませんでした"
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    // MARK: - Library

    @discardableResult
    func addToLibrary(_ book: OpenBDParsedBook) -> Manga? {
        let seriesTitle = book.series ?? book.title
        guard let mangaId = repository.upsertManga(
            title: seriesTitle,
            author: book.author,
            publisher: book.publisher,
            coverImageURL: book.coverImageURL,
            totalVolumes: nil
        ) else { return nil }

        let volumeNumber = book.volumeNumber ?? 1
        repository.upsertVolume(
            mangaId: mangaId,
            volumeNumber: volumeNumber,
            isbn: book.isbn,
            title: book.title,
            coverImageURL: book.coverImageURL,
            publishedAt: book.publishedAt
        )
        return repository.fetchManga(id: mangaId)
    }
}
