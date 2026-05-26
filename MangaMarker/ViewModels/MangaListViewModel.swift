import Foundation

@MainActor
final class MangaListViewModel: ObservableObject {
    @Published private(set) var items: [MangaWithProgress] = []
    @Published private(set) var isCheckingNewReleases = false
    @Published var searchText: String = ""
    @Published var hideCompleted: Bool = false

    private let repository: MangaRepository
    private let newReleaseChecker: NewReleaseChecker
    /// 一覧表示時に 1 回でチェックする最大シリーズ数。登録数が多くても画面表示をブロックしない。
    /// この数以下なら毎回 (再チェック間隔内を除き) 全件、多い場合は最も古い順にこの数だけチェックする。
    private let autoCheckBatchSize = 8

    init(repository: MangaRepository, newReleaseChecker: NewReleaseChecker) {
        self.repository = repository
        self.newReleaseChecker = newReleaseChecker
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

    /// 一覧表示時のバックグラウンド新刊チェック (非ブロッキング)。
    /// 未完シリーズのうち最後にチェックしてから最も時間が経った順に最大 `autoCheckBatchSize` 件だけ処理し、
    /// 各件チェック後に一覧を更新する。登録数が多くても画面表示や操作はブロックしない。
    /// 個々のシリーズには再チェック間隔があるため、短時間に何度開いても API を叩きすぎない。
    func autoCheckNewReleases() async {
        let targets = repository.fetchAllManga()
            .filter { !$0.isCompleted }
            .sorted { newReleaseChecker.lastChecked($0.id) < newReleaseChecker.lastChecked($1.id) }
            .prefix(autoCheckBatchSize)
        guard !targets.isEmpty else { return }

        isCheckingNewReleases = true
        defer { isCheckingNewReleases = false }
        for manga in targets {
            let didCheck = await newReleaseChecker.check(manga: manga)
            if didCheck { reload() }
        }
    }

    /// Pull to Refresh 用。未完シリーズ全件を再チェック間隔を無視して更新する。
    func refreshAllNewReleases() async {
        isCheckingNewReleases = true
        defer { isCheckingNewReleases = false }
        await newReleaseChecker.checkAll(force: true)
        reload()
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
