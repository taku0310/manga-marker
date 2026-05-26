import XCTest
@testable import MangaMarker

final class MangaRepositoryTests: XCTestCase {
    var repository: MangaRepository!

    override func setUp() {
        super.setUp()
        repository = MangaRepository(db: DatabaseManager.shared)
    }

    func test_upsertAndFetchManga() {
        let id = repository.upsertManga(
            title: "テスト漫画",
            author: "作者A",
            publisher: "出版社X",
            coverImageURL: nil,
            totalVolumes: 10
        )
        XCTAssertNotNil(id)
        let fetched = repository.fetchManga(id: id!)
        XCTAssertEqual(fetched?.title, "テスト漫画")
        XCTAssertEqual(fetched?.author, "作者A")
        repository.deleteManga(id: id!)
    }

    func test_volumeReadToggle() {
        let mangaId = repository.upsertManga(
            title: "ボリュームテスト",
            author: "",
            publisher: nil,
            coverImageURL: nil,
            totalVolumes: nil
        )!
        let vid = repository.upsertVolume(
            mangaId: mangaId,
            volumeNumber: 1,
            isbn: "9784000000000",
            title: "1巻",
            coverImageURL: nil,
            publishedAt: nil
        )!
        repository.setVolumeRead(id: vid, read: true)
        let volumes = repository.fetchVolumes(mangaId: mangaId)
        XCTAssertEqual(volumes.first?.isRead, true)
        repository.deleteManga(id: mangaId)
    }

    func test_resetReadStatus() {
        let mangaId = repository.upsertManga(
            title: "リセットテスト", author: "", publisher: nil, coverImageURL: nil, totalVolumes: nil
        )!
        for n in 1...3 {
            let vid = repository.upsertVolume(mangaId: mangaId, volumeNumber: n, isbn: nil, title: nil, coverImageURL: nil, publishedAt: nil)!
            repository.setVolumeRead(id: vid, read: true)
        }
        XCTAssertEqual(repository.fetchVolumes(mangaId: mangaId).filter(\.isRead).count, 3)

        repository.resetReadStatus(mangaId: mangaId)
        let volumes = repository.fetchVolumes(mangaId: mangaId)
        XCTAssertTrue(volumes.allSatisfy { !$0.isRead && $0.readAt == nil })
        // 「次に読む」は最小巻 (1巻) に戻る
        XCTAssertEqual(volumes.first(where: { !$0.isRead })?.volumeNumber, 1)
        repository.deleteManga(id: mangaId)
    }
}
