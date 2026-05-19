import SwiftUI

struct MangaDetailView: View {
    @StateObject var viewModel: MangaDetailViewModel
    @State private var showingAddByISBN = false
    @State private var inputISBN = ""

    var body: some View {
        List {
            Section {
                header
            }

            if let next = viewModel.nextUnreadVolume {
                Section("次に読む") {
                    NextVolumeCard(volume: next) {
                        viewModel.toggleRead(next)
                    }
                }
            }

            Section("巻一覧") {
                if viewModel.volumes.isEmpty {
                    Text("登録された巻がまだありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.volumes) { volume in
                    VolumeRow(
                        volume: volume,
                        isNext: viewModel.nextUnreadVolume?.id == volume.id,
                        onToggle: { viewModel.toggleRead(volume) },
                        onMarkUpTo: { viewModel.markReadUpTo(volume) },
                        onDelete: { viewModel.deleteVolume(volume) }
                    )
                }
            }
        }
        .navigationTitle(viewModel.manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.addEmptyVolume()
                    } label: {
                        Label("空の巻を追加", systemImage: "plus.circle")
                    }
                    Button {
                        showingAddByISBN = true
                    } label: {
                        Label("ISBNで追加", systemImage: "barcode")
                    }
                    Button {
                        viewModel.toggleCompleted()
                    } label: {
                        Label(viewModel.manga.isCompleted ? "完結を解除" : "完結としてマーク",
                              systemImage: viewModel.manga.isCompleted ? "arrow.uturn.backward" : "checkmark.seal")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("ISBNで追加", isPresented: $showingAddByISBN) {
            TextField("ISBN(13桁)", text: $inputISBN)
                .keyboardType(.numberPad)
            Button("追加") {
                let code = inputISBN
                inputISBN = ""
                Task { await viewModel.addVolume(byISBN: code) }
            }
            Button("キャンセル", role: .cancel) { inputISBN = "" }
        }
        .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear { viewModel.reload() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImageView(urlString: viewModel.manga.coverImageURL, width: 100, height: 140)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.manga.title).font(.title3.bold())
                Text(viewModel.manga.displayAuthor).font(.subheadline).foregroundStyle(.secondary)
                if let p = viewModel.manga.publisher { Text(p).font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: viewModel.progressRatio)
                    .tint(.accentColor)
                Text("\(viewModel.readCount) / \(viewModel.totalCount) 巻 読了")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NextVolumeCard: View {
    let volume: Volume
    let onRead: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(urlString: volume.coverImageURL, width: 60, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(volume.volumeNumber)巻").font(.title3.bold())
                if let title = volume.title { Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Button {
                onRead()
            } label: {
                Label("読了", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.accentColor.opacity(0.08))
    }
}

private struct VolumeRow: View {
    let volume: Volume
    let isNext: Bool
    let onToggle: () -> Void
    let onMarkUpTo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: volume.isRead ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(volume.isRead ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(volume.volumeNumber)巻").font(.subheadline.bold())
                    if isNext {
                        Text("NEXT")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                if let title = volume.title { Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let isbn = volume.isbn { Text("ISBN: \(isbn)").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let date = volume.publishedAt {
                Text(date, format: .dateTime.year().month()).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onMarkUpTo()
            } label: {
                Label("ここまで読了", systemImage: "checkmark.seal")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}
