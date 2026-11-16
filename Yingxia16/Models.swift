import Foundation

// MARK: - Loose JSON helpers
// TVBox configs mix strings and numbers for the same key, so everything is
// parsed as [String: Any] instead of strict Codable structs.

func jsonString(_ value: Any?) -> String {
    guard let value = value else { return "" }
    if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

func jsonInt(_ value: Any?) -> Int {
    guard let value = value else { return 0 }
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String { return Int(s) ?? 0 }
    return 0
}

func jsonArray(_ value: Any?) -> [[String: Any]] {
    if let a = value as? [[String: Any]] { return a }
    if let a = value as? [Any] { return a.compactMap { $0 as? [String: Any] } }
    return []
}

func jsonObject(_ value: Any?) -> [String: Any] {
    if let d = value as? [String: Any] { return d }
    return [:]
}

// MARK: - Models

struct Subscription: Identifiable, Equatable {
    var id: String { url }
    let url: String
    let name: String
}

struct Site: Identifiable, Equatable {
    var id: String { key + "|" + api }
    let key: String
    let name: String
    let type: Int
    let api: String
    let searchable: Int
    let subscriptionName: String

    var asDict: [String: String] {
        return ["key": key, "name": name, "type": String(type), "api": api,
                "searchable": String(searchable), "subscriptionName": subscriptionName]
    }

    static func from(_ d: [String: Any]) -> Site {
        return Site(key: jsonString(d["key"]),
                    name: jsonString(d["name"]),
                    type: jsonInt(d["type"]),
                    api: jsonString(d["api"]),
                    searchable: jsonInt(d["searchable"]),
                    subscriptionName: jsonString(d["subscriptionName"]))
    }
}

struct LiveSource: Identifiable, Equatable {
    var id: String { url }
    let name: String
    let url: String

    var asDict: [String: String] { return ["name": name, "url": url] }

    static func from(_ d: [String: Any]) -> LiveSource {
        return LiveSource(name: jsonString(d["name"]), url: jsonString(d["url"]))
    }
}

struct VClass: Identifiable, Equatable {
    var id: String { typeId }
    let typeId: String
    let name: String
}

struct Video: Identifiable, Equatable {
    var id: String { siteKey + "_" + vodId }
    let siteKey: String
    let siteName: String
    let api: String
    let vodId: String
    let title: String
    let pic: String
    let remark: String
    let typeName: String
    let typeId: String

    var asDict: [String: String] {
        return ["siteKey": siteKey, "siteName": siteName, "api": api, "vodId": vodId,
                "title": title, "pic": pic, "remark": remark,
                "typeName": typeName, "typeId": typeId]
    }

    static func from(_ d: [String: Any]) -> Video {
        return Video(siteKey: jsonString(d["siteKey"]),
                     siteName: jsonString(d["siteName"]),
                     api: jsonString(d["api"]),
                     vodId: jsonString(d["vodId"]),
                     title: jsonString(d["title"]),
                     pic: jsonString(d["pic"]),
                     remark: jsonString(d["remark"]),
                     typeName: jsonString(d["typeName"]),
                     typeId: jsonString(d["typeId"]))
    }
}

struct Episode: Identifiable, Equatable {
    var id: String { name + "|" + url }
    let name: String
    let url: String
}

struct EpisodeGroup: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let episodes: [Episode]
}

struct Detail: Equatable {
    let title: String
    let pic: String
    let desc: String
    let year: String
    let area: String
    let actor: String
    let director: String
    let groups: [EpisodeGroup]
}

struct Channel: Identifiable, Equatable {
    var id: String { name + "|" + url }
    let name: String
    let logo: String
    let group: String
    let url: String
}
