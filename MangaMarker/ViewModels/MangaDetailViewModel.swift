import Foundation

@MainActor
final class MangaDetailViewModel: ObservableObject {
    @Published private(set) var manga: Manga
    @Published private(set) var volumes: [Volume] = []
    @Published var isAddingVolume: Bool = false
    @Published var errorMessage: String?

    private let repository: MangaRepository
    private let openBDService: OpenBDService

    init(manga: Manga, repository: MangaRepository, openBDService: OpenBDService) {
        self.manga = manga
        self.repository = repository
        self.openBDService = openBDService
    }

    var nextUnreadVolume: Volume? {
        volumes.first { !$0.isRead }
    }

    var readCount: Int { volumes.filter(\.isRead).count }
    var totalCount: Int { manga.totalVolumes ?? volumes.count }
    var progressRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(readCount) / Double(totalCount)
    }

    func reload() {
        guard let updated = repository.fetchManga(id: manga.id) else { return }
        manga = updated
        volumes = repository.fetchVolumes(mangaId: manga.id)
    }

    func toggleRead(_ volume: Volume) {
        repository.setVolumeRead(id: volume.id, read: !volume.isRead)
        reload()
    }

    func markReadUpTo(_ volume: Volume) {
        for v in volumes where v.volumeNumber <= volume.volumeNumber {
            if !v.isRead { repository.setVolumeRead(id: v.id, read: true) }
        }
        reload()
    }

    func deleteVolume(_ volume: Volume) {
        repository.deleteVolume(id: volume.id)
        reload()
    }

    func toggleCompleted() {
        repository.setMangaCompleted(id: manga.id, completed: !manga.isCompleted)
        reload()
    }

    func addEmptyVolume() {
        let next = (volumes.map(\.volumeNumber).max() ?? 0) + 1
        repository.upsertVolume(
            mangaId: manga.id,
            volumeNumber: next,
            isbn: nil,
            title: nil,
            coverImageURL: nil,
            publishedAt: nil
        )
        reload()
    }

    func addVolume(byISBN isbn: String) async {
        isAddingVolume = true
        defer { isAddingVolume = false }
        do {
            let book = try await openBDService.fetch(isbn: isbn)
            let volumeNumber = book.volumeNumber ?? ((volumes.map(\.volumeNumber).max() ?? 0) + 1)
            repository.upsertVolume(
                mangaId: manga.id,
                volumeNumber: volumeNumber,
                isbn: book.isbn,
                title: book.title,
                coverImageURL: book.coverImageURL,
                publishedAt: book.publishedAt
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
