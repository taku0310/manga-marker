import Foundation

struct Manga: Identifiable, Hashable, Codable {
    var id: Int64
    var title: String
    var author: String
    var publisher: String?
    var coverImageURL: String?
    var totalVolumes: Int?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    var displayAuthor: String {
        author.isEmpty ? "著者不明" : author
    }
}

struct Volume: Identifiable, Hashable, Codable {
    var id: Int64
    var mangaId: Int64
    var volumeNumber: Int
    var isbn: String?
    var title: String?
    var coverImageURL: String?
    var publishedAt: Date?
    var isRead: Bool
    var readAt: Date?
    var createdAt: Date
}

struct MangaWithProgress: Identifiable, Hashable {
    let manga: Manga
    let readVolumeCount: Int
    let registeredVolumeCount: Int
    let nextUnreadVolume: Volume?
    let latestRegisteredVolume: Volume?

    var id: Int64 { manga.id }

    var progressText: String {
        if let total = manga.totalVolumes {
            return "\(readVolumeCount) / \(total) 巻 読了"
        }
        return "\(readVolumeCount) / \(registeredVolumeCount) 巻 読了"
    }

    var progressRatio: Double {
        let denom = manga.totalVolumes ?? registeredVolumeCount
        guard denom > 0 else { return 0 }
        return Double(readVolumeCount) / Double(denom)
    }
}
