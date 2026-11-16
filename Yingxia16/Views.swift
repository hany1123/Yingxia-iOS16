import SwiftUI
import UIKit

// MARK: - Root

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView() }
                .tabItem { Label("首页", systemImage: "film") }.tag(0)
            NavigationStack { SearchView() }
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { LiveView() }
                .tabItem { Label("直播", systemImage: "tv") }.tag(2)
            NavigationStack { LibraryView() }
                .tabItem { Label("收藏", systemImage: "heart") }.tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }
    }
}

// MARK: - View models (ObservableObject, iOS 16 safe)

final class SiteViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var classes: [VClass] = []
    @Published var selectedClass = ""
    @Published var page = 1
    @Published var isLoading = false
    @Published var message = ""
    private var siteID = ""

    func load(site: Site?) {
        guard let site = site else { return }
        if siteID == site.id && (!videos.isEmpty || isLoading) { return }
        siteID = site.id
        page = 1
        selectedClass = ""
        Task { await self.fetch(site: site) }
    }

    func reload(site: Site?) {
        guard let site = site else { return }
        siteID = site.id
        Task { await self.fetch(site: site) }
    }

    func choose(_ classID: String, site: Site?) {
        selectedClass = classID
        page = 1
        Task { await self.fetch(site: site) }
    }

    func changePage(_ delta: Int, site: Site?) {
        page = max(1, page + delta)
        Task { await self.fetch(site: site) }
    }

    func fetch(site: Site?) async {
        guard let site = site else { return }
        let cls = selectedClass
        let pg = page
        var params: [String: String] = ["pg": String(pg)]
        if !cls.isEmpty { params["t"] = cls }
        await MainActor.run {
            self.isLoading = true
            self.message = ""
        }
        let result: ([Video], [VClass])
        do {
            result = try await API.fetchList(site: site, params: params)
        } catch {
            result = ([], [])
        }
        let videos = result.0
        let classes = result.1
        await MainActor.run {
            self.isLoading = false
            if !classes.isEmpty { self.classes = classes }
            self.videos = videos
            self.message = videos.isEmpty ? "没有读到内容，可切换分类或换一个源" : ""
        }
    }
}

final class DetailViewModel: ObservableObject {
    @Published var detail: Detail?
    @Published var isLoading = false

    func load(_ video: Video) async {
        await MainActor.run { self.isLoading = true }
        let d = try? await API.fetchDetail(video)
        await MainActor.run {
            self.detail = d
            self.isLoading = false
        }
    }
}

final class SearchViewModel: ObservableObject {
    @Published var results: [Video] = []
    @Published var isLoading = false
    @Published var searched = false

    func search(_ text: String, sites: [Site]) async {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        await MainActor.run {
            self.isLoading = true
            self.searched = true
        }
        let limited = Array(sites.prefix(20))
        let final: [Video] = await withTaskGroup(of: [Video].self, returning: [Video].self) { group in
            for site in limited {
                group.addTask {
                    let r = try? await API.fetchList(site: site, params: ["wd": key])
                    return r?.0 ?? []
                }
            }
            var all: [Video] = []
            for await part in group { all.append(contentsOf: part) }
            return all
        }
        await MainActor.run {
            self.results = final
            self.isLoading = false
        }
    }
}

final class LiveViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var message = ""

    func load(_ source: LiveSource?) async {
        guard let source = source else { return }
        await MainActor.run { self.isLoading = true }
        let result: [Channel]
        do {
            result = try await API.fetchChannels(source)
        } catch {
            result = []
        }
        let final = result
        await MainActor.run {
            self.isLoading = false
            self.channels = final
            self.message = final.isEmpty ? "直播源为空或格式不支持" : "\(final.count) 个频道"
        }
    }
}

// MARK: - Shared poster

struct PosterImage: View {
    let urlString: String

    var body: some View {
        Group {
            if !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "film").font(.largeTitle).foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "film").font(.largeTitle).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct VideoCard: View {
    let video: Video

    var body: some View {
        NavigationLink(destination: DetailView(video: video)) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground))
                    PosterImage(urlString: video.pic)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(video.title).font(.subheadline).lineLimit(1)
                Text(video.remark.isEmpty ? video.typeName : video.remark)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var vm = SiteViewModel()
    @State private var selectedSiteID = ""
    @State private var showSettings = false

    private var currentSite: Site? {
        if let s = store.sites.first(where: { $0.id == selectedSiteID }) { return s }
        return store.sites.first
    }

    var body: some View {
        Group {
            if store.sites.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack").font(.system(size: 54)).foregroundColor(.secondary)
                    Text("没有可用的点播源").font(.title3)
                    Text(store.statusMessage)
                        .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Text("订阅若全是 type 3 插件源，可到「直播」页看直播，或在「设置」里手动添加 JSON 源 / 查看读取诊断。")
                        .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("打开设置") { showSettings = true }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("源", selection: $selectedSiteID) {
                            ForEach(store.sites) { site in
                                Text(site.name).tag(site.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedSiteID) { _ in
                            vm.reload(site: currentSite)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button("全部") { vm.choose("", site: currentSite) }
                                    .buttonStyle(.bordered)
                                ForEach(vm.classes) { item in
                                    Button(item.name) { vm.choose(item.typeId, site: currentSite) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
                            ForEach(vm.videos) { video in
                                VideoCard(video: video)
                            }
                        }

                        if vm.isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        if !vm.message.isEmpty {
                            Text(vm.message).font(.footnote).foregroundColor(.secondary)
                        }

                        HStack {
                            Button("上一页") { vm.changePage(-1, site: currentSite) }
                                .disabled(vm.page <= 1)
                            Spacer()
                            Text("第 \(vm.page) 页").font(.footnote)
                            Spacer()
                            Button("下一页") { vm.changePage(1, site: currentSite) }
                        }
                        .font(.footnote)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("映匣 16")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onAppear {
            if selectedSiteID.isEmpty { selectedSiteID = store.sites.first?.id ?? "" }
            vm.load(site: currentSite)
        }
        .onChange(of: store.sites.count) { _ in
            if !store.sites.contains(where: { $0.id == selectedSiteID }) {
                selectedSiteID = store.sites.first?.id ?? ""
                vm.reload(site: currentSite)
            }
        }
        .refreshable {
            await store.refresh()
            vm.reload(site: currentSite)
        }
    }
}

// MARK: - Detail

struct DetailView: View {
    let video: Video
    @EnvironmentObject private var store: Store
    @StateObject private var vm = DetailViewModel()
    @State private var playURL: String?
    @State private var playTitle = ""
    @State private var selectedGroup = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground))
                        PosterImage(urlString: video.pic)
                    }
                    .frame(width: 110, height: 155)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(video.title).font(.headline)
                        Text(video.siteName).font(.caption).foregroundColor(.secondary)
                        if !video.remark.isEmpty {
                            Text(video.remark).font(.caption).foregroundColor(.secondary)
                        }
                        Button(store.isFavorite(video) ? "取消收藏" : "收藏") {
                            store.toggleFavorite(video)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let d = vm.detail {
                    if !d.desc.isEmpty {
                        Text(d.desc).font(.footnote).foregroundColor(.secondary)
                    }
                    if !d.actor.isEmpty { Text("主演：\(d.actor)").font(.caption) }
                    if !d.director.isEmpty { Text("导演：\(d.director)").font(.caption) }
                }

                if vm.isLoading { ProgressView() }

                if let d = vm.detail, !d.groups.isEmpty {
                    Picker("线路", selection: $selectedGroup) {
                        ForEach(0..<d.groups.count, id: \.self) { index in
                            Text(d.groups[index].name).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    let group = d.groups[min(max(selectedGroup, 0), d.groups.count - 1)]
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                        ForEach(group.episodes) { episode in
                            Button(episode.name) {
                                playTitle = video.title + " · " + episode.name
                                playURL = episode.url
                                store.addHistory(video)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                } else if vm.detail != nil {
                    Text("该源未返回可播放地址").font(.footnote).foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(video) }
        .fullScreenCover(isPresented: Binding(
            get: { playURL != nil },
            set: { if !$0 { playURL = nil } }
        )) {
            if let u = playURL {
                PlayerView(url: u, title: playTitle)
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var vm = SearchViewModel()
    @State private var query = ""

    var body: some View {
        List {
            if vm.isLoading {
                HStack { ProgressView(); Text("搜索中…").font(.footnote) }
            }
            if vm.searched && !vm.isLoading && vm.results.isEmpty {
                Text("没有找到结果").foregroundColor(.secondary)
            }
            ForEach(vm.results) { video in
                NavigationLink(destination: DetailView(video: video)) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color(UIColor.secondarySystemBackground))
                            PosterImage(urlString: video.pic)
                        }
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title).font(.subheadline).lineLimit(1)
                            Text(video.siteName).font(.caption).foregroundColor(.secondary)
                            Text(video.remark).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "输入片名，跨源搜索")
        .onSubmit(of: .search) {
            Task { await vm.search(query, sites: store.sites) }
        }
    }
}

// MARK: - Live

struct LiveView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var vm = LiveViewModel()
    @State private var selectedID = ""
    @State private var playing: Channel?

    private var source: LiveSource? {
        if let s = store.lives.first(where: { $0.id == selectedID }) { return s }
        return store.lives.first
    }

    var body: some View {
        Group {
            if store.lives.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tv").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("订阅里没有直播源").font(.headline)
                    Text("在设置中添加含 lives 的 TVBox 订阅")
                        .font(.footnote).foregroundColor(.secondary)
                }
            } else {
                List {
                    Section {
                        Picker("直播源", selection: $selectedID) {
                            ForEach(store.lives) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if !vm.message.isEmpty {
                        Text(vm.message).font(.footnote).foregroundColor(.secondary)
                    }
                    let groups = Dictionary(grouping: vm.channels, by: { $0.group })
                    ForEach(Array(groups.keys).sorted(), id: \.self) { key in
                        Section(key) {
                            ForEach(groups[key] ?? []) { channel in
                                Button(channel.name) { playing = channel }
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("直播")
        .onAppear {
            if selectedID.isEmpty { selectedID = store.lives.first?.id ?? "" }
        }
        .onChange(of: selectedID) { _ in
            Task { await vm.load(source) }
        }
        .onChange(of: store.lives.count) { _ in
            if selectedID.isEmpty { selectedID = store.lives.first?.id ?? "" }
            Task { await vm.load(source) }
        }
        .task { await vm.load(source) }
        .fullScreenCover(item: $playing) { channel in
            PlayerView(url: channel.url, title: channel.name)
        }
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section("收藏") {
                if store.favorites.isEmpty {
                    Text("暂无收藏").foregroundColor(.secondary)
                }
                ForEach(store.favorites) { video in
                    NavigationLink(destination: DetailView(video: video)) {
                        VStack(alignment: .leading) {
                            Text(video.title).lineLimit(1)
                            Text(video.siteName).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("观看历史") {
                if store.history.isEmpty {
                    Text("暂无记录").foregroundColor(.secondary)
                }
                ForEach(store.history) { video in
                    NavigationLink(destination: DetailView(video: video)) {
                        VStack(alignment: .leading) {
                            Text(video.title).lineLimit(1)
                            Text(video.siteName).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("收藏")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newURL = ""
    @State private var siteName = ""
    @State private var siteAPI = ""
    @State private var alertText = ""
    @State private var showAlert = false

    var body: some View {
        List {
            Section("订阅地址") {
                if store.subscriptions.isEmpty {
                    Text("尚未添加订阅").foregroundColor(.secondary)
                }
                ForEach(store.subscriptions) { sub in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.name).font(.subheadline)
                        Text(sub.url).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                .onDelete { offsets in store.removeSubscriptions(at: offsets) }

                HStack {
                    TextField("https://…/config.json", text: $newURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("添加") {
                        if store.addSubscription(newURL) {
                            newURL = ""
                        } else {
                            alertText = "地址无效或已经添加过"
                            showAlert = true
                        }
                    }
                }
            }

            Section("手动添加点播源（type 1 CMS）") {
                TextField("名称（可留空）", text: $siteName)
                TextField("API …/api.php/provide/vod/", text: $siteAPI)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("添加源") {
                    if store.addCustomSite(name: siteName, api: siteAPI) {
                        siteName = ""
                        siteAPI = ""
                    } else {
                        alertText = "需要完整的 http(s) API 地址，或该地址已添加过"
                        showAlert = true
                    }
                }
                ForEach(store.customSites) { site in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name).font(.subheadline)
                        Text(site.api).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                .onDelete { offsets in store.removeCustomSites(at: offsets) }
            }

            Section {
                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack {
                        Text("重新读取订阅")
                        Spacer()
                        if store.isRefreshing { ProgressView() }
                    }
                }
                Text(store.statusMessage).font(.footnote).foregroundColor(.secondary)
            }

            Section("读取诊断") {
                if store.diagnostics.isEmpty {
                    Text("点「重新读取订阅」后，这里会逐个显示地址的结果与源类型分布")
                        .font(.footnote).foregroundColor(.secondary)
                }
                ForEach(store.diagnostics, id: \.self) { line in
                    Text(line).font(.footnote).foregroundColor(.secondary)
                }
            }

            Section("兼容说明") {
                Text("iOS 16 精简分支，deployment target 16.0，可在 iOS 16.3 运行。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("type 3 插件源（JAR/JS/Python，如 csp_*）需要嵌入式 JVM / QuickJS 运行时，本版本不支持。订阅里若全是这类源，点播会为空，但直播源仍可使用。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("订阅地址必须返回 JSON 配置；填写网站主页（HTML）会解析失败。支持 JSON / base64 配置、多仓聚合 urls、相对路径 api 与 M3U/TXT 直播。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("不内置任何订阅地址，不提供媒体内容。请只添加自己有权访问的源。")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.1 · iOS 16").foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .alert(alertText, isPresented: $showAlert) {
            Button("好", role: .cancel) { }
        }
    }
}
