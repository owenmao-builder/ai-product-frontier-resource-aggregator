import AppKit
import SwiftUI
import WebKit
import Combine

@main
struct AINewsEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let store = NewsStore()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var dashboard: NSWindow?
    var settings: NSWindow?
    var webView: WKWebView?
    var observation: AnyCancellable?
    var dashboardRange = "24h"
    var webReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A single agent instance owns the menu-bar item and refresh timer.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.owen.AINewsMenu").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { others.first?.activate(); NSApp.terminate(nil); return }
        // Seed a visible position once; subsequent launches preserve the user's placement.
        // AppKit otherwise appends the item beyond the MacBook notch on a crowded menu bar.
        let positionKey = "NSStatusItem Preferred Position AINewsStatusItem"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(220.0, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "AINewsStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "AI 资讯")?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
            button.image?.isTemplate = true
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 680)
        popover.contentViewController = NSHostingController(rootView: MenuContent(store: store, openDashboard: { [weak self] in self?.showDashboard() }, openSettings: { [weak self] in self?.showSettings() }))
        store.onUpdate = { [weak self] in self?.updateStatus(); self?.pushToWeb() }
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        updateStatus()
        store.start()
        if CommandLine.arguments.contains("--show-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showPopover() }
        }
        if CommandLine.arguments.contains("--show-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showDashboard() }
        }
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }
        let iconOnly = store.preferences.compactTitle
        statusItem.length = iconOnly ? NSStatusItem.squareLength : NSStatusItem.variableLength
        button.imagePosition = iconOnly ? .imageOnly : .imageLeading
        button.title = ""
        if let first = store.items.sorted(by: { store.rating(for: $0).sortScore > store.rating(for: $1).sortScore }).first {
            let rating = store.rating(for: first)
            if !iconOnly {
                let title = store.title(for: first)
                let headline = String(title.prefix(11)) + (title.count > 11 ? "…" : "")
                button.title = headline + " " + rating.displayScore
            }
            button.toolTip = store.title(for: first) + "\n" + rating.displayScore + " · " + rating.statusLabel + "\n点击预览 · 右键更多选项"
        } else {
            button.toolTip = store.loading ? "AI 资讯 · 正在拉取最新消息" : "AI 资讯 · 点击预览消息"
        }
        button.setAccessibilityLabel("AI 资讯菜单栏预览")
    }

    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, action) in [("立即拉取", #selector(refreshAction)), ("打开完整看板", #selector(dashboardAction)), ("AI 产品", #selector(productsAction)), ("更新与评分设置", #selector(settingsAction))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 AI 资讯", action: #selector(quitAction), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc func refreshAction() { Task { await store.refresh() } }
    @objc func dashboardAction() { showDashboard() }
    @objc func productsAction() { store.section = "products"; showPopover() }
    @objc func settingsAction() { showSettings() }
    @objc func quitAction() { NSApp.terminate(nil) }

    func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 580), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "AI 资讯 · 设置"; window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        settings?.contentView = NSHostingView(rootView: SettingsContent(store: store, close: { [weak self] in self?.settings?.close() }))
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }

    func showDashboard() {
        popover.performClose(nil)
        if dashboard == nil {
            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "newsBridge")
            config.userContentController.addUserScript(WKUserScript(source: "window.__AI_NATIVE__ = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let web = WKWebView(frame: .zero, configuration: config)
            web.navigationDelegate = self; web.uiDelegate = self
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "AI 资讯聚合 · 菜单栏版"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 650, height: 480); window.contentView = web; window.center()
            dashboard = window; webView = web
            if let root = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true) {
                web.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
            }
        }
        NSApp.activate(ignoringOtherApps: true); dashboard?.makeKeyAndOrderFront(nil)
        pushToWeb()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
            let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let range = body["range"] as? String ?? "24h"
        guard ["24h", "7d"].contains(range) else { return }
        switch action {
        case "ready", "load":
            webReady = true; dashboardRange = range; pushToWeb()
            if store.snapshots[range] == nil || (range == "7d" && action == "load") { Task { await store.refresh(range: range) } }
        case "refresh":
            dashboardRange = range
            Task { await store.refresh(range: range) }
        case "settings": showSettings()
        case "section":
            if let section = body["section"] as? String, ["news", "products"].contains(section) { store.section = section }
        case "preview": showPopover()
        case "read":
            if let url = body["url"] as? String, let item = store.snapshots.values.flatMap({ $0.items }).first(where: { $0.url == url }) { store.markRead(item) }
        default: break
        }
    }

    func pushToWeb() {
        guard webReady, let web = webView else { return }
        let snapshot = store.dashboardData(range: dashboardRange)
        var payload: [String: Any] = ["range": dashboardRange, "section": store.section, "loading": store.loading, "scoring": store.scoring,
            "error": store.error as Any? ?? NSNull(), "aiError": store.aiError as Any? ?? NSNull(),
            "lastChecked": store.lastChecked.map { timestamp($0) } as Any? ?? NSNull(), "refreshMinutes": store.preferences.refreshMinutes]
        if let snapshot, let data = try? JSONEncoder().encode(snapshot), let json = try? JSONSerialization.jsonObject(with: data) { payload["data"] = json }
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: bytes, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.dispatchEvent(new CustomEvent('ai-news-native', {detail: \(json)}));", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if webReady { pushToWeb() } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else if url.isFileURL, let root = Bundle.main.resourceURL?.appendingPathComponent("web").standardizedFileURL.path, url.standardizedFileURL.path.hasPrefix(root + "/") { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return true }
}
