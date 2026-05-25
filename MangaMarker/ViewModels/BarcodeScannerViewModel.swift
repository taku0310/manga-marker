import Foundation

@MainActor
final class BarcodeScannerViewModel: ObservableObject {
    @Published var scannedISBN: String?
    @Published var lastResult: OpenBDParsedBook?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false
    @Published var savedMangaId: Int64?

    private let openBDService: OpenBDService
    private let repository: MangaRepository

    init(openBDService: OpenBDService, repository: MangaRepository) {
        self.openBDService = openBDService
        self.repository = repository
    }

    func handle(scanned code: String) async {
        let digits = code.filter(\.isNumber)
        guard digits.count == 13 else { return }
        // JANコード規約上、書籍は978/979で始まる
        guard digits.hasPrefix("978") || digits.hasPrefix("979") else {
            errorMessage = "書籍バーコードではありません"
            return
        }
        guard scannedISBN != digits else { return }
        scannedISBN = digits

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let book = try await openBDService.fetch(isbn: digits)
            lastResult = book
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveToLibrary() {
        guard let book = lastResult else { return }
        let seriesTitle = book.seriesTitle
        guard let mangaId = repository.upsertManga(
            title: seriesTitle,
            author: book.author,
            publisher: book.publisher,
            coverImageURL: book.coverImageURL,
            totalVolumes: nil
        ) else { return }

        let volumeNumber = book.volumeNumber ?? 1
        repository.upsertVolume(
            mangaId: mangaId,
            volumeNumber: volumeNumber,
            isbn: book.isbn,
            title: book.title,
            coverImageURL: book.coverImageURL,
            publishedAt: book.publishedAt
        )
        savedMangaId = mangaId
    }

    func reset() {
        scannedISBN = nil
        lastResult = nil
        errorMessage = nil
        savedMangaId = nil
    }
}
