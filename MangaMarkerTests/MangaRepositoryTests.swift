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
}
