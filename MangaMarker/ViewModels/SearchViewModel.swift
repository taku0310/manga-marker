import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [OpenBDParsedBook] = []
    @Published private(set) var isSearching: Bool = false
    @Published var errorMessage: String?

    private let openBDService: OpenBDService
    private let repository: MangaRepository

    init(openBDService: OpenBDService, repository: MangaRepository) {
        self.openBDService = openBDService
        self.repository = repository
    }

    /// ISBNとして妥当ならOpenBDで単一検索、それ以外は将来拡張のため何もしない。
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let digits = trimmed.filter(\.isNumber)
        if digits.count == 13 || digits.count == 10 {
            do {
                let book = try await openBDService.fetch(isbn: digits)
                results = [book]
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        } else {
            // タイトル検索はOpenBD単独では対応不可（将来拡張）
            errorMessage = "ISBN(10桁または13桁)を入力してください。タイトル検索は将来対応します。"
            results = []
        }
    }

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
