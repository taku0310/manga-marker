import SwiftUI

struct MangaRowView: View {
    let item: MangaWithProgress

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: item.manga.coverImageURL, width: 56, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.manga.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(item.manga.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: item.progressRatio)
                    .tint(.accentColor)

                HStack(spacing: 6) {
                    Text(item.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.manga.isCompleted {
                        Text("完結")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                if let next = item.nextUnreadVolume {
                    NextVolumeBadge(volume: next)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NextVolumeBadge: View {
    let volume: Volume

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill")
            Text("次に読む: \(volume.volumeNumber)巻")
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

struct CoverImageView: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            Image(systemName: "book.closed").foregroundStyle(.secondary)
        }
    }
}
