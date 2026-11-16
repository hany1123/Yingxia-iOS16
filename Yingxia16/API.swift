import Foundation

enum APIError: LocalizedError {
    case badURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址无效"
        case .badResponse: return "服务器返回异常"
        }
    }
}

enum M3U {
    static func parse(_ text: String) -> [Channel] {
        var result: [Channel] = []
        var pendingName = ""
        var pendingLogo = ""
        var currentGroup = "默认"
        let lines = text.components(separatedBy: .newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF") {
                pendingName = extinfName(line)
                pendingLogo = attribute(line, key: "tvg-logo")
                let g = attribute(line, key: "group-title")
                if !g.isEmpty { currentGroup = g }
                continue
            }
            if line.hasPrefix("#") {
                if line.contains("#genre#") {
                    let n = line.replacingOccurrences(of: ",#genre#", with: "")
                        .replacingOccurrences(of: "#genre#", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { currentGroup = n }
                }
                continue
            }
            if line.contains(",") {
                let parts = line.components(separatedBy: ",")
                let url = parts.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                if url.contains("://") {
                    result.append(Channel(name: name.isEmpty ? url : name, logo: "", group: currentGroup, url: url))
                    continue
                }
            }
            if line.contains("://") {
                result.append(Channel(name: pendingName.isEmpty ? line : pendingName,
                                      logo: pendingLogo, group: currentGroup, url: line))
                pendingName = ""
                pendingLogo = ""
            }
        }
        return result
    }

    private static func extinfName(_ line: String) -> String {
        guard let r = line.range(of: ",", options: .backwards) else { return "" }
        return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private static func attribute(_ line: String, key: String) -> String {
        guard let r = line.range(of: key + "=\"") else { return "" }
        let rest = String(line[r.upperBound...])
        guard let e = rest.range(of: "\"") else { return "" }
        return String(rest[..<e.lowerBound])
    }
}

enum API {
    static func request(_ urlString: String, ua: String? = nil) async throws -> Data {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let custom = ua ?? ""
        let agent = custom.isEmpty
            ? "Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15"
            : custom
        req.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.badResponse
        }
        return data
    }

    static func requestText(_ url: String, ua: String? = nil) async throws -> String {
        let data = try await request(url, ua: ua)
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    static func query(_ api: String, _ params: [String: String]) -> String {
        guard var comps = URLComponents(string: api) else { return api }
        var dict: [String: String] = [:]
        for item in comps.queryItems ?? [] { dict[item.name] = item.value ?? "" }
        for (k, v) in params { dict[k] = v }
        comps.queryItems = dict.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.string ?? api
    }

    // MARK: Subscription config

    static func fetchConfig(_ url: String, subscriptionName: String) async throws -> ConfigResult {
        let data = try await request(url)
        return try parseConfig(data: data, baseURL: url, subscriptionName: subscriptionName)
    }

    static func parseConfig(data: Data, baseURL: String, subscriptionName: String) throws -> ConfigResult {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let head = String(text.prefix(300)).lowercased()
        if head.contains("<!doctype") || head.contains("<html") || head.contains("<head") {
            throw ConfigError.htmlPage
        }

        var obj: Any?
        if let utf8 = text.data(using: .utf8) {
            obj = try? JSONSerialization.jsonObject(with: utf8)
        }
        if obj == nil {
            // Some TVBox configs are distributed as a whole base64 blob.
            let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
            if compact.count > 40, let decoded = Data(base64Encoded: compact, options: .ignoreUnknownCharacters) {
                obj = try? JSONSerialization.jsonObject(with: decoded)
            }
        }
        guard let raw = obj else { throw ConfigError.notJSON }

        var root = jsonObject(raw)
        if root["sites"] == nil {
            for key in ["data", "config", "result"] {
                let nested = jsonObject(root[key])
                if nested["sites"] != nil { root = nested; break }
            }
        }

        let rawSites = jsonArray(root["sites"])
        var sites: [Site] = []
        var pluginCount = 0
        for item in rawSites {
            let type = jsonInt(item["type"])
            // type 3 = JAR/JS/Python plugin source. Needs the embedded JVM/QuickJS
            // runtime that this iOS 16 slim build deliberately does not ship.
            if type == 3 { pluginCount += 1; continue }
            var api = jsonString(item["api"])
            if api.isEmpty { api = jsonString(item["ext"]) }
            if !api.isEmpty && !api.contains("://") {
                api = absoluteURL(api, relativeTo: baseURL)
            }
            guard api.contains("://") else { continue }
            let key = jsonString(item["key"])
            let name = jsonString(item["name"])
            sites.append(Site(key: key.isEmpty ? api : key,
                              name: name.isEmpty ? "未命名源" : name,
                              type: type,
                              api: api,
                              searchable: jsonInt(item["searchable"]),
                              subscriptionName: subscriptionName))
        }

        var lives: [LiveSource] = []
        for item in jsonArray(root["lives"]) {
            var liveURL = jsonString(item["url"])
            if liveURL.isEmpty { liveURL = jsonString(item["ext"]) }
            if !liveURL.isEmpty && !liveURL.contains("://") {
                liveURL = absoluteURL(liveURL, relativeTo: baseURL)
            }
            if liveURL.contains("://") {
                let liveName = jsonString(item["name"])
                lives.append(LiveSource(name: liveName.isEmpty ? "直播" : liveName,
                                        url: liveURL,
                                        ua: jsonString(item["ua"])))
            }
        }

        var nested: [String] = []
        if let urls = root["urls"] as? [Any] {
            for entry in urls {
                if let d = entry as? [String: Any] {
                    let s = jsonString(d["url"])
                    if s.contains("://") && s != baseURL { nested.append(s) }
                } else {
                    let s = jsonString(entry)
                    if s.contains("://") && s != baseURL { nested.append(s) }
                }
            }
        }

        return ConfigResult(sites: sites, lives: lives,
                            totalSites: rawSites.count,
                            pluginSites: pluginCount,
                            nestedURLs: nested)
    }

    private static func absoluteURL(_ path: String, relativeTo base: String) -> String {
        guard let b = URL(string: base) else { return path }
        if path.hasPrefix("//") { return (b.scheme ?? "https") + ":" + path }
        if path.hasPrefix("/") {
            var comps = URLComponents(url: b, resolvingAgainstBaseURL: false)
            comps?.path = path
            comps?.query = nil
            comps?.fragment = nil
            return comps?.string ?? path
        }
        return URL(string: path, relativeTo: b)?.absoluteString ?? path
    }

    // MARK: VOD list / categories / search

    static func fetchList(site: Site, params: [String: String]) async throws -> ([Video], [VClass]) {
        let attempts: [[String: String]] = [["ac": "list"], ["ac": "videolist"]]
        for attempt in attempts {
            var merged = attempt
            for (k, v) in params { merged[k] = v }
            guard let data = try? await request(query(site.api, merged)),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            let root = jsonObject(obj)
            var items = jsonArray(root["list"])
            if items.isEmpty { items = jsonArray(root["data"]) }
            let classes = parseClasses(root["class"])
            if !items.isEmpty || !classes.isEmpty {
                return (parseVideos(items, site: site), classes)
            }
        }
        return ([], [])
    }

    private static func parseClasses(_ raw: Any?) -> [VClass] {
        var result: [VClass] = []
        for item in jsonArray(raw) {
            let id = jsonString(item["type_id"])
            let name = jsonString(item["type_name"])
            if !id.isEmpty && !name.isEmpty {
                result.append(VClass(typeId: id, name: name))
            }
        }
        return result
    }

    private static func parseVideos(_ items: [[String: Any]], site: Site) -> [Video] {
        var result: [Video] = []
        for item in items {
            let id = jsonString(item["vod_id"])
            var title = jsonString(item["vod_name"])
            if title.isEmpty { title = jsonString(item["videoName"]) }
            if id.isEmpty && title.isEmpty { continue }
            var remark = jsonString(item["vod_remarks"])
            if remark.isEmpty { remark = jsonString(item["vod_note"]) }
            result.append(Video(siteKey: site.key,
                                siteName: site.name,
                                api: site.api,
                                vodId: id.isEmpty ? title : id,
                                title: title.isEmpty ? "未命名" : title,
                                pic: jsonString(item["vod_pic"]),
                                remark: remark,
                                typeName: jsonString(item["type_name"]),
                                typeId: jsonString(item["type_id"])))
        }
        return result
    }

    // MARK: Detail / play URLs

    static func fetchDetail(_ video: Video) async throws -> Detail {
        let attempts: [[String: String]] = [
            ["ac": "detail", "ids": video.vodId],
            ["ac": "videolist", "ids": video.vodId]
        ]
        var picked: [String: Any] = [:]
        for attempt in attempts {
            guard let data = try? await request(query(video.api, attempt)),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            let root = jsonObject(obj)
            var items = jsonArray(root["list"])
            if items.isEmpty { items = jsonArray(root["data"]) }
            if let match = items.first(where: { jsonString($0["vod_id"]) == video.vodId }) {
                picked = match
                break
            }
            if let first = items.first { picked = first }
            if !picked.isEmpty { break }
        }
        let fromRaw = jsonString(picked["vod_play_from"])
        let urlRaw = jsonString(picked["vod_play_url"])
        let names = fromRaw.isEmpty ? [] : fromRaw.components(separatedBy: "$$$")
        let blocks = urlRaw.isEmpty ? [] : urlRaw.components(separatedBy: "$$$")
        var groups: [EpisodeGroup] = []
        for (index, block) in blocks.enumerated() {
            var episodes: [Episode] = []
            for rawLine in block.components(separatedBy: "#") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                let parts = line.components(separatedBy: "$")
                if parts.count >= 2 {
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let url = parts.dropFirst().joined(separator: "$").trimmingCharacters(in: .whitespaces)
                    if url.contains("://") {
                        episodes.append(Episode(name: name.isEmpty ? "第\(episodes.count + 1)集" : name, url: url))
                    }
                } else if line.contains("://") {
                    episodes.append(Episode(name: "第\(episodes.count + 1)集", url: line))
                }
            }
            if !episodes.isEmpty {
                let groupName: String
                if index < names.count && !names[index].isEmpty {
                    groupName = names[index]
                } else {
                    groupName = "线路 \(index + 1)"
                }
                groups.append(EpisodeGroup(name: groupName, episodes: episodes))
            }
        }
        var desc = jsonString(picked["vod_content"])
        if desc.isEmpty { desc = jsonString(picked["vod_blurb"]) }
        return Detail(title: video.title,
                      pic: video.pic,
                      desc: desc,
                      year: jsonString(picked["vod_year"]),
                      area: jsonString(picked["vod_area"]),
                      actor: jsonString(picked["vod_actor"]),
                      director: jsonString(picked["vod_director"]),
                      groups: groups)
    }

    static func fetchChannels(_ source: LiveSource) async throws -> [Channel] {
        let text = try await requestText(source.url, ua: source.ua)
        return M3U.parse(text)
    }
}
