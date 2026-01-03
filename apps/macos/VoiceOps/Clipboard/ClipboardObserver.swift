import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ClipboardObserver {
    static let shared = ClipboardObserver(store: ClipboardStore.shared)

    private let store: ClipboardStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var ignoreUntil: Date?
    private var pendingRemoteURLs: Set<String> = []

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markInternalWrite(duration: TimeInterval = 0.6) {
        ignoreUntil = Date().addingTimeInterval(duration)
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if let ignoreUntil, ignoreUntil > Date() {
            return
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let result = readImageData() {
            store.recordSystemImage(result.data, appBundleID: bundleID, originalPath: result.originalPath)
            return
        }

        if let text = readText() {
            store.recordSystemText(text, appBundleID: bundleID)
        }
    }

    private func readText() -> String? {
        if let text = pasteboard.string(forType: .string) {
            return text
        }
        if let rtfData = pasteboard.data(forType: .rtf) {
            if let attr = try? NSAttributedString(data: rtfData, options: [:], documentAttributes: nil) {
                return attr.string
            }
        }
        return nil
    }

    private func readImageData() -> (data: Data, originalPath: String?)? {
        if let data = dataForImageTypes(),
           let png = pngData(from: data) {
            return (png, nil)
        }

        if let fileURL = fileURLFromPasteboard(),
           let png = pngData(from: fileURL) {
            return (png, fileURL.path)
        }

        if let image = NSImage(pasteboard: pasteboard),
           let data = pngData(from: image) {
            return (data, nil)
        }

        if let remoteURL = remoteURLFromPasteboard() {
            fetchRemoteImage(url: remoteURL)
        }

        return nil
    }

    private func dataForImageTypes() -> Data? {
        let types = [
            UTType.png.identifier,
            UTType.tiff.identifier,
            "public.webp",
            UTType.jpeg.identifier,
            UTType.heic.identifier,
            UTType.heif.identifier,
            UTType.gif.identifier,
            UTType.bmp.identifier
        ]
        for type in types {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)) {
                return data
            }
        }
        return nil
    }

    private func fileURLFromPasteboard() -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            return url
        }
        if let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    private func remoteURLFromPasteboard() -> URL? {
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString),
           url.scheme?.hasPrefix("http") == true,
           isLikelyImageURL(url) {
            return url
        }
        if let urlString = pasteboard.string(forType: .string),
           let url = URL(string: urlString),
           url.scheme?.hasPrefix("http") == true,
           isLikelyImageURL(url) {
            return url
        }
        return nil
    }

    private func fetchRemoteImage(url: URL) {
        let key = url.absoluteString
        guard !pendingRemoteURLs.contains(key) else { return }
        pendingRemoteURLs.insert(key)

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            defer { self.pendingRemoteURLs.remove(key) }
            guard let data, !data.isEmpty else { return }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return }
            if let length = response?.expectedContentLength, length > 12_000_000 { return }
            if data.count > 12_000_000 { return }
            if let mime = response?.mimeType, !mime.hasPrefix("image/") { return }
            guard let imageData = self.pngData(from: data) else { return }
            self.store.recordSystemImage(imageData, appBundleID: bundleID, originalPath: nil)
        }.resume()
    }

    private func pngData(from image: NSImage) -> Data? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return pngData(from: cgImage)
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return pngData(from: tiff)
    }

    private func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return pngData(from: cgImage)
    }

    private func pngData(from url: URL) -> Data? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return pngData(from: cgImage)
        }
        if let data = try? Data(contentsOf: url) {
            return pngData(from: data)
        }
        return nil
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func isLikelyImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "heic", "heif", "avif"]
        if imageExts.contains(ext) { return true }
        let query = url.query?.lowercased() ?? ""
        if query.contains("fmt=") || query.contains("format=") { return true }
        return false
    }
}
