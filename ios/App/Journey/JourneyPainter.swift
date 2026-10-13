// SPDX-License-Identifier: GPL-3.0-only
// The Journey's painter (ios/prd.json IOS-018): a web view running the page
// npm run ios:generate builds from desktop's own brush engine and Journey
// painter. murmur asks it for pictures and shows them as images, or, for
// the ceremony, shows the web view itself under native text, so every word
// on the Journey stays a native view. The page is one file in the app
// bundle, with read access to its own folder only; its content policy
// refuses every fetch, and the web view refuses every navigation but that
// one file's first load.
import UIKit
import WebKit

/// The page in the app bundle.
enum JourneyPage {
    static var url: URL? {
        Bundle.main.url(forResource: "journey", withExtension: "html", subdirectory: "web")
    }

    /// A web view for the page: nothing kept between launches, no windows,
    /// and the page's messages to murmur.
    @MainActor static func configuration(messages: JourneyMessages) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(messages, name: "journey")
        return configuration
    }
}

/// Lets the page's own file load once and nothing after it. If iOS ends the
/// page's process (it can, to free memory), the page loads once more.
final class OneLoad: NSObject, WKNavigationDelegate {
    private let allowed: URL
    private var loaded = false
    var onRestart: (@MainActor () -> Void)?

    init(allowing url: URL) {
        allowed = url
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let allow = !loaded && action.request.url?.standardizedFileURL == allowed.standardizedFileURL
        if allow { loaded = true }
        decisionHandler(allow ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        MainActor.assumeIsolated { onRestart?() }
        webView.loadFileURL(allowed, allowingReadAccessTo: allowed.deletingLastPathComponent())
    }
}

/// The page's messages to murmur: for now, that it is ready. The web view's
/// content controller holds this strongly, so it holds nothing back.
final class JourneyMessages: NSObject, WKScriptMessageHandler {
    var onReady: (@MainActor () -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard (message.body as? [String: Any])?["type"] as? String == "ready" else { return }
        MainActor.assumeIsolated { onReady?() }
    }
}

/// A picture the page painted, with the road's words to set natively.
struct JourneyPicture {
    let image: UIImage
    /// On the road: each belt group's name and where it starts, in points.
    var groups: [(name: String, x: CGFloat)] = []
    /// On the road: where you stand, in points.
    var you: CGFloat?
}

@MainActor final class JourneyPainter {
    enum Failure: Error { case noPage, notReady, badPicture }

    /// The painter for the Journey's pictures, never on screen.
    static let shared = JourneyPainter()

    let web: WKWebView
    private let navigation: OneLoad?
    private let messages = JourneyMessages()
    private var ready = false
    /// The page never said ready in time (or there is none): later asks
    /// fail at once, until the page starts over.
    private var gaveUp = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(page: URL? = JourneyPage.url) {
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), configuration: JourneyPage.configuration(messages: messages))
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.accessibilityElementsHidden = true
        navigation = page.map { OneLoad(allowing: $0) }
        web.navigationDelegate = navigation
        messages.onReady = { [weak self] in self?.becameReady() }
        navigation?.onRestart = { [weak self] in
            self?.ready = false
            self?.gaveUp = false
        }
        if let page {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            gaveUp = true
        }
    }

    private func becameReady() {
        ready = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    /// Waits for the page to say it is ready. A cold start of the page's
    /// process can take a few seconds; the Journey reads plainly meanwhile.
    func waitUntilReady(seconds: Double = 15) async throws {
        if ready { return }
        if gaveUp { throw Failure.notReady }
        let deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.ready else { return }
            self.gaveUp = true
            for continuation in self.waiting { continuation.resume() }
            self.waiting = []
        }
        await withCheckedContinuation { waiting.append($0) }
        deadline.cancel()
        guard ready else { throw Failure.notReady }
    }

    /// One picture from the page.
    func picture(_ request: JourneyArtwork, scale: CGFloat) async throws -> JourneyPicture {
        try await waitUntilReady()
        var asked = request.fields
        asked["scale"] = scale
        let answer = try await web.callAsyncJavaScript("return window.murmurJourney.picture(request)", arguments: ["request": asked], contentWorld: .page)
        guard let body = answer as? [String: Any], let png = body["png"] as? String,
              let comma = png.firstIndex(of: ","), let data = Data(base64Encoded: String(png[png.index(after: comma)...])),
              let image = UIImage(data: data, scale: scale)
        else { throw Failure.badPicture }
        var picture = JourneyPicture(image: image)
        if let groups = body["groups"] as? [[String: Any]] {
            picture.groups = groups.compactMap { group in
                guard let name = group["name"] as? String, let x = group["x"] as? Double else { return nil }
                return (name, CGFloat(x))
            }
        }
        picture.you = (body["you"] as? Double).map { CGFloat($0) }
        return picture
    }

    /// The promotion ceremony, painted on this web view's own canvases at
    /// this size: animated, or finished at once with Reduce Motion.
    func ceremony(rank: String, size: CGSize, reduced: Bool) async throws {
        try await waitUntilReady()
        let request: [String: Any] = ["rank": rank, "width": size.width, "height": size.height, "reduced": reduced]
        let answer = try await web.callAsyncJavaScript("return window.murmurJourney.ceremony(request)", arguments: ["request": request], contentWorld: .page)
        guard answer as? Bool == true else { throw Failure.badPicture }
    }
}

/// Where practice stands, as the page reads it.
struct JourneyStanding: Hashable {
    let rank: String
    let next: String?
    let words: Int
    let days: Int

    var fields: [String: Any] {
        ["rank": rank, "next": next ?? NSNull(), "words": words, "days": days]
    }
}

/// A picture the page paints, sized in points.
enum JourneyArtwork: Hashable {
    /// drop runs 0 to 1 while the newest stripe's tape slaps on.
    case belt(belt: String, stripes: Int, width: Double, height: Double, drop: Double?)
    case road(JourneyStanding)
    case words(JourneyStanding, width: Double, height: Double)
    case tallies(JourneyStanding, width: Double, height: Double)
    case stamp(id: String, got: Bool, seed: Int, size: Double)

    var fields: [String: Any] {
        switch self {
        case let .belt(belt, stripes, width, height, drop):
            var fields: [String: Any] = ["kind": "belt", "belt": belt, "stripes": stripes, "width": width, "height": height]
            if let drop { fields["drop"] = drop }
            return fields
        case let .road(standing):
            return ["kind": "road", "standing": standing.fields]
        case let .words(standing, width, height):
            return ["kind": "words", "standing": standing.fields, "width": width, "height": height]
        case let .tallies(standing, width, height):
            return ["kind": "tallies", "standing": standing.fields, "width": width, "height": height]
        case let .stamp(id, got, seed, size):
            return ["kind": "stamp", "id": id, "got": got, "seed": seed, "size": size]
        }
    }
}
