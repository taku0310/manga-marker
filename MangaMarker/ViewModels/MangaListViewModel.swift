import Foundation

@MainActor
final class MangaListViewModel: ObservableObject {
    @Published private(set) var items: [MangaWithProgress] = []
    @Published var searchText: String = ""
    @Published var hideCompleted: Bool = false

    private let repository: MangaRepository

    init(repository: MangaRepository) {
        self.repository = repository
    }

    var filteredItems: [MangaWithProgress] {
        var list = items
        if hideCompleted {
            list = list.filter { !$0.manga.isCompleted }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.manga.title.lowercased().contains(q)
                || $0.manga.author.lowercased().contains(q)
            }
        }
        return list
    }

    func reload() {
        items = repository.fetchAllMangaWithProgress()
    }

    func toggleCompleted(_ manga: Manga) {
        repository.setMangaCompleted(id: manga.id, completed: !manga.isCompleted)
        reload()
    }

    func delete(at offsets: IndexSet) {
        let target = offsets.map { filteredItems[$0].manga.id }
        target.forEach { repository.deleteManga(id: $0) }
        reload()
    }
}
