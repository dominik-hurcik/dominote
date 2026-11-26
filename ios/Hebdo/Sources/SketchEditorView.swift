import SwiftUI
import WebKit

/// Offline Excalidraw whiteboard powered by the exact same bundle as desktop Hebdo.
struct SketchEditorView: View {
    @EnvironmentObject private var store: NoteStore
    @Environment(\.colorScheme) private var colorScheme

    let path: String

    private var title: String {
        let name = (path as NSString).lastPathComponent
        if name.hasSuffix(".excalidraw") { return String(name.dropLast(".excalidraw".count)) }
        return name
    }

    var body: some View {
        SketchWebView(
            initialJSON: store.readNote(at: path),
            theme: colorScheme == .dark ? "dark" : "light",
            onSave: { json in
                store.writeNote(at: path, content: json)
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SketchWebView: UIViewRepresentable {
    let initialJSON: String
    let theme: String
    let onSave: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(initialJSON: initialJSON, theme: theme, onSave: onSave)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalSketchSchemeHandler(), forURLScheme: "hebdo-sketch")
        config.userContentController.add(context.coordinator, name: "hebdoSketch")
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        context.coordinator.webView = webView

        if let url = URL(string: "hebdo-sketch://app/sketch.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentTheme != theme {
            context.coordinator.currentTheme = theme
            webView.evaluateJavaScript("window.__hebdoTheme && window.__hebdoTheme('\(theme)')")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript("window.__hebdoFlush && window.__hebdoFlush()")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "hebdoSketch")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        let initialJSON: String
        var currentTheme: String
        let onSave: (String) -> Void
        private var lastSaved: String

        init(initialJSON: String, theme: String, onSave: @escaping (String) -> Void) {
            self.initialJSON = initialJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? NoteStore.emptySketchJSON
                : initialJSON
            self.lastSaved = self.initialJSON
            self.currentTheme = theme
            self.onSave = onSave
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "ready" {
                guard let encoded = try? JSONSerialization.data(withJSONObject: [initialJSON, currentTheme]),
                      let args = String(data: encoded, encoding: .utf8) else { return }
                webView?.evaluateJavaScript("window.__hebdoInit && window.__hebdoInit(...\(args))")
            } else if type == "save", let json = body["json"] as? String, json != lastSaved {
                lastSaved = json
                Task { @MainActor in onSave(json) }
            }
        }
    }
}

/// Serves bundled sketch.html and ui/sketch/* assets offline with proper MIME types.
private final class LocalSketchSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let relPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard let base = Bundle.main.resourceURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let fileURL = base.appendingPathComponent(relPath)
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = Self.mimeType(for: fileURL.pathExtension.lowercased())
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
