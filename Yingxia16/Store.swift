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

    private let defaults = UserDefaults.standard

    init() {
        let urls = defaults.stringArray(forKey: "subscriptions") ?? []
        subscriptions = urls.map { Subscription(url: $0, name: Self.hostName($0)) }
        favorites = loadVideos("favorites")
        history = loadVideos("history")
        sites = loadDictArray("cachedSites").map { Site.from($0) }
        lives = loadDictArray("cachedLives").map { LiveSource.from($0) }
        if !sites.isEmpty { statusMessage = "已缓存 \(sites.count) 个源" }
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
        }
        let list = subscriptions
        var allSites: [Site] = []
        var allLives: [LiveSource] = []
        var failures = 0
        for sub in list {
            do {
                let (s, l) = try await API.fetchConfig(sub.url, subscriptionName: sub.name)
                allSites.append(contentsOf: s)
                allLives.append(contentsOf: l)
            } catch {
                failures += 1
            }
        }
        let finalSites = allSites
        let finalLives = allLives
        await MainActor.run {
            self.sites = finalSites
            self.lives = finalLives
            self.isRefreshing = false
            if finalSites.isEmpty {
                self.statusMessage = failures > 0
                    ? "订阅读取失败：请检查地址或网络"
                    : "未发现 JSON 源（type 3 插件源不受支持）"
            } else {
                self.statusMessage = "\(finalSites.count) 个源 · \(finalLives.count) 个直播源"
            }
            self.saveDictArray("cachedSites", finalSites.map { $0.asDict })
            self.saveDictArray("cachedLives", finalLives.map { $0.asDict })
        }
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
