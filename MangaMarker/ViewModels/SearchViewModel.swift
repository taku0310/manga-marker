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
    /// シリーズ単位に集約した検索結果 (各シリーズ代表 1 件)。
    @Published private(set) var results: [OpenBDParsedBook] = []
    @Published private(set) var isSearching: Bool = false
    /// ライブラリ追加中のシリーズ代表 ID。
    @Published private(set) var addingBookId: String?
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
            results = SeriesVolumeFilter.representatives(from: [book])
        } catch {
            // OpenBD で見つからない場合は書誌検索サービス (楽天Kobo→Google) にフォールバック
            do {
                let raw = try await bookSearchService.searchByTitle("isbn:\(digits)")
                results = SeriesVolumeFilter.representatives(from: raw)
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
            let raw = try await bookSearchService.searchByTitle(input)
            // シリーズ単位に集約し、各シリーズ代表 1 件のみ表示する
            results = SeriesVolumeFilter.representatives(from: raw)
            if results.isEmpty {
                errorMessage = "該当する漫画が見つかりませんでした"
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    // MARK: - Library

    /// 検索結果の代表を起点に、そのシリーズの全巻を取得してライブラリへ登録する。
    @discardableResult
    func addToLibrary(_ representative: OpenBDParsedBook) async -> Manga? {
        let seriesTitle = representative.series ?? representative.title
        addingBookId = representative.id
        defer { addingBookId = nil }

        // シリーズ名で全巻取得。取得できなければ代表 1 件のみ登録。
        var volumes = (try? await bookSearchService.searchAllVolumes(seriesName: seriesTitle)) ?? []
        if volumes.isEmpty { volumes = [representative] }

        let coverImageURL = volumes
            .min(by: { ($0.volumeNumber ?? Int.max) < ($1.volumeNumber ?? Int.max) })?
            .coverImageURL ?? representative.coverImageURL

        guard let mangaId = repository.upsertManga(
            title: seriesTitle,
            author: representative.author,
            publisher: representative.publisher,
            coverImageURL: coverImageURL,
            totalVolumes: nil
        ) else { return nil }

        for book in volumes {
            repository.upsertVolume(
                mangaId: mangaId,
                volumeNumber: book.volumeNumber ?? 1,
                isbn: book.isbn,
                title: book.title,
                coverImageURL: book.coverImageURL,
                publishedAt: book.publishedAt
            )
        }
        return repository.fetchManga(id: mangaId)
    }
}
