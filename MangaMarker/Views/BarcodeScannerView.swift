import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @StateObject var viewModel: BarcodeScannerViewModel
    @EnvironmentObject private var deps: AppDependencies
    @State private var navigateManga: Manga?

    var body: some View {
        ZStack {
            CameraScannerRepresentable { code in
                Task { await viewModel.handle(scanned: code) }
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                resultPanel
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
            }
        }
        .navigationTitle("スキャン")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $navigateManga) { manga in
            MangaDetailView(
                viewModel: MangaDetailViewModel(
                    manga: manga,
                    repository: deps.repository,
                    openBDService: deps.openBDService
                )
            )
        }
        .onChange(of: viewModel.savedMangaId) { _, newValue in
            if let id = newValue, let manga = deps.repository.fetchManga(id: id) {
                navigateManga = manga
            }
            viewModel.reset()
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if viewModel.isProcessing {
            HStack { ProgressView(); Text("書誌情報を取得中…") }
        } else if let book = viewModel.lastResult {
            HStack(spacing: 12) {
                CoverImageView(urlString: book.coverImageURL, width: 64, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.headline).lineLimit(2)
                    Text(book.author).font(.caption).foregroundStyle(.secondary)
                    if let v = book.volumeNumber { Text("第\(v)巻").font(.caption) }
                }
                Spacer()
                Button("追加") {
                    viewModel.saveToLibrary()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let msg = viewModel.errorMessage {
            Text(msg).foregroundStyle(.red)
        } else {
            Label("書籍バーコードをかざしてください", systemImage: "barcode.viewfinder")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UIViewControllerRepresentable

struct CameraScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var lastScannedAt: Date = .distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func configureCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    self.setupSession()
                } else {
                    self.showPermissionDeniedLabel()
                }
            }
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce]
        }
        session.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)

        addOverlay()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func addOverlay() {
        let frame = CGRect(x: 40, y: view.bounds.midY - 80, width: view.bounds.width - 80, height: 160)
        let overlay = CAShapeLayer()
        overlay.path = UIBezierPath(roundedRect: frame, cornerRadius: 12).cgPath
        overlay.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        overlay.fillColor = UIColor.clear.cgColor
        overlay.lineWidth = 2
        view.layer.addSublayer(overlay)
    }

    private func showPermissionDeniedLabel() {
        let label = UILabel()
        label.text = "カメラへのアクセスが拒否されました。\n設定アプリから許可してください。"
        label.numberOfLines = 0
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }

        // 同一コードの連打を抑制
        let now = Date()
        if now.timeIntervalSince(lastScannedAt) < 1.5 { return }
        lastScannedAt = now

        // 触覚フィードバック
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        onScan?(value)
    }
}
