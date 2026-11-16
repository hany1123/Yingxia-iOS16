import Foundation
import Combine

final class Store: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var sites: [Site] = []
    @Published var lives: [LiveSource] = []
    @Published var favorites: [Video] = []
    @Published var history: [Video] = []
    @Published var isRefreshing = false
    @Published var statusMessage = "尚未添加订阅"
    @Published var diagnostics: [String] = []
    @Published var customSites: [Site] = []

    private let defaults = UserDefaults.standard

    init() {
        let urls = defaults.stringArray(forKey: "subscriptions") ?? []
        subscriptions = urls.map { Subscription(url: $0, name: Self.hostName($0)) }
        favorites = loadVideos("favorites")
        history = loadVideos("history")
        sites = loadDictArray("cachedSites").map { Site.from($0) }
        lives = loadDictArray("cachedLives").map { LiveSource.from($0) }
        customSites = loadDictArray("customSites").map { Site.from($0) }
        if !sites.isEmpty || !lives.isEmpty {
            statusMessage = "已缓存 \(sites.count) 个点播源 · \(lives.count) 个直播源"
        }
    }

    private static func hostName(_ raw: String) -> String {
        guard let u = URL(string: raw), let h = u.host else { return "订阅" }
        return h
    }

    // MARK: Persistence

    private func saveDictArray(_ key: String, _ items: [[String: String]]) {
        if let data = try? JSONSerialization.data(withJSONObject: items, options: []) {
            defaults.set(data, forKey: key)
        }
    }

    private func loadDictArray(_ key: String) -> [[String: Any]] {
        guard let data = defaults.data(forKey: key),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let arr = obj as? [[String: Any]] else { return [] }
        return arr
    }

    private func saveVideos(_ key: String, _ items: [Video]) {
        saveDictArray(key, items.map { $0.asDict })
    }

    private func loadVideos(_ key: String) -> [Video] {
        return loadDictArray(key).map { Video.from($0) }
    }

    // MARK: Subscriptions

    func addSubscription(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else { return false }
        guard !subscriptions.contains(where: { $0.url == url }) else { return false }
        var arr = subscriptions
        arr.append(Subscription(url: url, name: Self.hostName(url)))
        subscriptions = arr
        defaults.set(arr.map { $0.url }, forKey: "subscriptions")
        Task { await self.refresh() }
        return true
    }

    func removeSubscriptions(at offsets: IndexSet) {
        var arr = subscriptions
        for index in Array(offsets).sorted(by: >) {
            if index < arr.count { arr.remove(at: index) }
        }
        subscriptions = arr
        defaults.set(arr.map { $0.url }, forKey: "subscriptions")
        Task { await self.refresh() }
    }

    func refresh() async {
        await MainActor.run {
            self.isRefreshing = true
            self.statusMessage = "正在读取订阅…"
            self.diagnostics = []
        }
        let list = subscriptions
        let manual = customSites
        var allSites: [Site] = manual
        var allLives: [LiveSource] = []
        var lines: [String] = []
        var visited: Set<String> = []
        var queue: [(String, String, Int)] = list.map { ($0.url, $0.name, 0) }
        var cursor = 0

        // Breadth-first: expand aggregate subscriptions ("urls") one level deep.
        while cursor < queue.count {
            let (url, label, depth) = queue[cursor]
            cursor += 1
            if visited.contains(url) { continue }
            visited.insert(url)
            do {
                let r = try await API.fetchConfig(url, subscriptionName: label)
                allSites.append(contentsOf: r.sites)
                allLives.append(contentsOf: r.lives)
                var line = "\(label)：共 \(r.totalSites) 个源"
                if r.pluginSites > 0 {
                    line += "，\(r.pluginSites) 个 type 3 插件源（本版本不支持）"
                }
                if !r.sites.isEmpty { line += "，可用 \(r.sites.count) 个" }
                if !r.lives.isEmpty { line += "，直播 \(r.lives.count) 个" }
                if r.sites.isEmpty && r.pluginSites > 0 {
                    line += " → 点播为空"
                }
                lines.append(line)
                if depth < 1 {
                    for nested in r.nestedURLs.prefix(5) {
                        queue.append((nested, "↳ " + label, depth + 1))
                    }
                }
            } catch {
                lines.append("\(label)：读取失败 — \(error.localizedDescription)")
            }
        }
        if !manual.isEmpty {
            lines.append("手动添加：\(manual.count) 个 JSON 源")
        }
        let finalSites = allSites
        let finalLives = allLives
        let finalLines = lines
        await MainActor.run {
            self.sites = finalSites
            self.lives = finalLives
            self.diagnostics = finalLines
            self.isRefreshing = false
            if finalSites.isEmpty && finalLives.isEmpty {
                self.statusMessage = "没有可用源，展开「读取诊断」查看原因"
            } else {
                self.statusMessage = "\(finalSites.count) 个点播源 · \(finalLives.count) 个直播源"
            }
            self.saveDictArray("cachedSites", finalSites.map { $0.asDict })
            self.saveDictArray("cachedLives", finalLives.map { $0.asDict })
        }
    }

    // MARK: Manually added type 1 (CMS JSON) sources

    func addCustomSite(name: String, api raw: String) -> Bool {
        let api = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard api.contains("://"), let u = URL(string: api), u.scheme != nil else { return false }
        guard !customSites.contains(where: { $0.api == api }) else { return false }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = Site(key: "custom-" + api,
                        name: title.isEmpty ? (u.host ?? "自定义源") : title,
                        type: 1,
                        api: api,
                        searchable: 1,
                        subscriptionName: "手动添加")
        var arr = customSites
        arr.append(site)
        customSites = arr
        sites.append(site)
        saveDictArray("customSites", arr.map { $0.asDict })
        saveDictArray("cachedSites", sites.map { $0.asDict })
        return true
    }

    func removeCustomSites(at offsets: IndexSet) {
        var arr = customSites
        for index in Array(offsets).sorted(by: >) {
            if index < arr.count { arr.remove(at: index) }
        }
        customSites = arr
        saveDictArray("customSites", arr.map { $0.asDict })
        Task { await self.refresh() }
    }

    // MARK: Favorites / history

    func isFavorite(_ video: Video) -> Bool {
        return favorites.contains(video)
    }

    func toggleFavorite(_ video: Video) {
        if let index = favorites.firstIndex(of: video) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        saveVideos("favorites", favorites)
    }

    func addHistory(_ video: Video) {
        var arr = history.filter { $0.id != video.id }
        arr.insert(video, at: 0)
        if arr.count > 50 { arr = Array(arr.prefix(50)) }
        history = arr
        saveVideos("history", arr)
    }
}
