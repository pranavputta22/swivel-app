import UIKit
import WebKit
import AVFoundation

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var content: WKUserContentController!
    private let haptics = Haptics()
    private let keep = Keep()
    private let gameCenter = GameCenter()
    private let reminder = Reminder()
    private let review = Review()
    private let store = Store()
    private var shown = false
    private var pageReady = false
    private var pendingLink: String?
    private var lastLink: (text: String, at: Date)?

    // Made once, as the app starts and before it has a window (AppDelegate). A link the app was
    // started with arrives through open(link:) before the page is loaded, and waits for it.
    init() {
        super.init(nibName: nil, bundle: nil)
        // set up before the app has finished launching, so a tap on a reminder that starts the app is heard
        reminder.onOpen = { [weak self] in self?.open(link: "swivel://daily") }
        reminder.start()
    }

    required init?(coder: NSCoder) {
        fatalError("GameViewController is made in code")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sky.color

        let content = WKUserContentController()
        // The page talks to the app through one handler; a weak proxy, so the two do not hold each other.
        content.add(WeakHandler(self), name: "swivel")
        self.content = content

        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let web = WKWebView(frame: view.bounds, configuration: config)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = Sky.color
        web.scrollView.backgroundColor = Sky.color
        web.scrollView.bounces = false
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.alpha = 0 // shown when the page says it has drawn
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        view.addSubview(web)
        webView = web

        keep.onCloudChange = { [weak self] progress in self?.send(progress: progress) }
        keep.start()
        gameCenter.start(host: self)
        review.noteDay()
        store.onChange = { [weak self] json in self?.call("__swivelFull", with: json) }
        store.start()
        // The game's music gives way to the player's own: the phone says when that starts and stops.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(otherAudioChanged), name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
        center.addObserver(self, selector: #selector(becameActive), name: UIScene.didActivateNotification, object: nil)
        haptics.prepare()
        load()

        // never wait on the page for long
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.reveal() }
    }

    private func load() {
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            assertionFailure("Web/index.html is missing from the app")
            return
        }
        pageReady = false
        // What the app has kept is handed to the page before the page's own script runs. It is made
        // afresh for every load, so a page put back after the system ended it gets today's copies,
        // and a link the app was started with is followed once and not again.
        var extra: [String: Any] = ["reminder": reminder.remembered, "rate": review.canRate, "full": store.handover]
        if let link = pendingLink {
            extra["open"] = link
            pendingLink = nil
        }
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(source: keep.handover(otherAudio: otherAudioPlaying, extra: extra),
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    private func reveal() {
        guard !shown else { return }
        shown = true
        UIView.animate(withDuration: 0.2) { self.webView.alpha = 1 }
    }

    // MARK: saying things to the page

    // Calls a function of the page's with one piece of text, written so that no text can break out of it.
    private func call(_ function: String, with text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let list = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.\(function) && window.\(function)(\(list)[0]);", completionHandler: nil)
    }

    // A change made on another of the player's devices, brought by iCloud while the game is open.
    private func send(progress: String) {
        call("__swivelProgress", with: progress)
    }

    private func send(reminder state: String) {
        call("__swivelReminder", with: state)
    }

    // MARK: the player's own music

    private var otherAudioPlaying: Bool {
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    @objc private func otherAudioChanged() {
        sendOtherAudio()
    }

    @objc private func becameActive() {
        sendOtherAudio()
        Task { await store.check() }
        review.noteDay()
        // back from the phone's Settings, perhaps with notifications now allowed
        reminder.recheck { [weak self] state in self?.send(reminder: state) }
    }

    private func sendOtherAudio() {
        webView.evaluateJavaScript("window.__swivelOtherAudio && window.__swivelOtherAudio(\(otherAudioPlaying ? "true" : "false"));",
                                   completionHandler: nil)
    }

    // MARK: links

    // A link the app was opened with (swivel://..., or the game's own page on the web), or a tap on a reminder.
    func open(link: String) {
        if let last = lastLink, last.text == link, Date().timeIntervalSince(last.at) < 3 { return } // the system can say it twice
        lastLink = (link, Date())
        if isViewLoaded && pageReady {
            call("__swivelOpen", with: link)
        } else {
            pendingLink = link // handed over when the page starts, or as soon as it says it is ready
        }
    }

    // MARK: sharing

    private func share(text: String?, link: String?, image: String? = nil) {
        var items: [Any] = []
        // a picture of the result (the page draws it), sent with the words
        if let image = image, image.count < 8_000_000, let data = Data(base64Encoded: image), let picture = UIImage(data: data) { items.append(picture) }
        if let text = text, !text.isEmpty { items.append(text) }
        if let link = link, let url = URL(string: link) { items.append(url) }
        guard !items.isEmpty, presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // an iPad shows this as a popover, which has to be told where it comes from
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    // MARK: the page's messages

    // numbers from the page, as whole numbers
    private func wholeNumbers(_ any: Any?) -> [String: Int] {
        guard let dict = any as? [String: Any] else { return [:] }
        return dict.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "swivel",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let data = body["data"] as? [String: Any]
        switch type {
        case "ready":
            pageReady = true
            if let link = pendingLink {
                pendingLink = nil
                call("__swivelOpen", with: link)
            }
            reveal()
        case "haptic":
            haptics.play(body["data"] as? String ?? "tap")
        case "store":
            if let store = body["data"] as? [String: String] { keep.save(store: store) }
        case "progress":
            if let progress = body["data"] as? String { keep.save(progress: progress) }
        case "copy":
            if let text = body["data"] as? String { UIPasteboard.general.string = text }
        case "share":
            share(text: data?["text"] as? String, link: data?["url"] as? String, image: data?["image"] as? String)
        case "game":
            gameCenter.report(feats: wholeNumbers(data?["feats"]), scores: wholeNumbers(data?["scores"]))
        case "gamecenter":
            gameCenter.open()
        case "moment":
            if let kind = data?["kind"] as? String { review.moment(kind, in: view.window?.windowScene) }
        case "rate":
            review.rate()
        case "buy":
            Task { await store.buy(in: view.window?.windowScene) }
        case "restore":
            Task { await store.restore() }
        case "remind":
            if let plan = data { reminder.apply(plan) { [weak self] state in self?.send(reminder: state) } }
        default:
            break
        }
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL || url.scheme == "about" { decisionHandler(.allow); return }
        // the game links nowhere; anything else is handed to the phone
        if url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    // (the page has started again: it is told what the phone is playing)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendOtherAudio()
    }

    // If the system ends the page's process to free memory, the game is put back; it resumes where it was.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }
}

// Lets the web view's content controller hold the handler without keeping the view controller alive.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
