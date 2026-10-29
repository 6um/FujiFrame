import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft: EditorDraft?
    @State private var moveLink: PhotoLink?
    @State private var removeLink: PhotoLink?
    @FocusState private var galleryFocused: Bool
    var body: some View {
        Group {
            if model.library == nil { welcome }
            else { workspace }
        }
        .sheet(item: $draft) { RecipeEditor(draft: $0).environmentObject(model) }
        .sheet(item: $moveLink) { MoveSheet(link: $0).environmentObject(model) }
        .sheet(item: $model.review) { ImportReviewView(session: $0) }
        .sheet(isPresented: $model.showResults) { importReport }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil && draft == nil && model.review == nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("移除这张样片？", isPresented: Binding(get: { removeLink != nil }, set: { if !$0 { removeLink = nil } }), titleVisibility: .visible) {
            Button("移除样片", role: .destructive) { if let link = removeLink { model.remove(link) }; removeLink = nil }
        } message: {
            Text("仅移除当前版本的关联。若其他版本也未使用此照片，资料库中的原图将移到系统废纸篓；你导入前的源文件不受影响。")
        }
    }
    var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.aperture").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("FujiFrame").font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("让每一套配方，都有值得回看的照片。").font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label("X-T5 配方", systemImage: "slider.horizontal.3")
                Text("·").padding(.horizontal, 5)
                Label("本地 JPEG 资料库", systemImage: "externaldrive")
            }.font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button("创建我的资料库…") { model.chooseLibrary(create: true) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("打开已有资料库…") { model.chooseLibrary(create: false) }.buttonStyle(.plain)
                Button("从备份恢复…") { model.restore() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.top, 12).disabled(model.busy)
            if model.busy { ProgressView(); Text(model.status).font(.caption) }
            Text("照片和配方只保存在你选择的本地文件夹中").font(.caption).foregroundStyle(.tertiary).padding(.top, 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var workspace: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "camera.aperture").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text("FujiFrame").font(.headline)
                        Text("X-T5 · 配方资料库").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { draft = EditorDraft(recipe: Recipe(), version: nil, isNew: true) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("创建配方").disabled(model.busy)
                }.padding(16)
                Button { model.choosePhotos() } label: { Label("智能导入…", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).disabled(model.busy).padding(.bottom, 12)
                TextField("搜索配方或照片", text: $model.search).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                Picker("胶片模拟", selection: $model.film) {
                    Text("全部胶片模拟").tag("")
                    ForEach(XT5.films, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().padding(12)
                List(selection: $model.selectedRecipe) {
                    ForEach(model.visibleRecipes) { recipe in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recipe.name).font(.headline).lineLimit(1)
                            Text(recipe.summary.isEmpty ? "尚无配方简介" : recipe.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            let versions = model.versions.filter { $0.recipeID == recipe.id }
                            Text("\(versions.count) 个版本 · \(model.links.filter { link in versions.contains { $0.id == link.versionID } }.count) 张样片")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 7).tag(recipe.id)
                    }
                }.listStyle(.sidebar)
                Divider()
                Toggle("查看已归档配方", isOn: $model.showArchived).toggleStyle(.checkbox).font(.caption).padding(12)
                Menu {
                    Button("在 Finder 显示资料库") { if let root = model.library?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) } }
                    Button("打开其他资料库…") { model.chooseLibrary(create: false) }
                    Button("创建资料库…") { model.chooseLibrary(create: true) }
                    Button("关闭资料库") { model.closeLibrary() }
                    Divider()
                    Button("备份资料库…") { model.backup() }
                    Button("从备份恢复…") { model.restore() }
                } label: { Label("资料库", systemImage: "externaldrive") }.padding([.horizontal, .bottom], 12).disabled(model.busy)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            VStack(spacing: 0) {
                if let recipe = model.recipe {
                    galleryHeader(recipe)
                    Divider()
                    if model.visibleLinks.isEmpty {
                        ContentUnavailableView {
                            Label("\(model.search.isEmpty && !model.filterDates && model.film.isEmpty ? "还没有样片" : "没有匹配的样片")", systemImage: "photo.on.rectangle.angled")
                        } description: {
                            Text("将 JPEG 拖到这里，自动建议配方；确认后才会导入。")
                        } actions: {
                            Button("智能导入 JPEG…") { model.choosePhotos() }.disabled(model.busy)
                        }.frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 18) {
                                ForEach(model.visibleLinks) { link in
                                    if let photo = model.photo(link), let library = model.library {
                                        PhotoCard(photo: photo, link: link, library: library, selected: model.selectedLink == link.id)
                                            .onTapGesture { model.selectedLink = link.id; galleryFocused = true }
                                            .contextMenu {
                                                Button("纠正所属版本…") { moveLink = link }.disabled(model.busy)
                                                Button("移除样片…", role: .destructive) { removeLink = link }.disabled(model.busy)
                                            }
                                    }
                                }
                            }.padding(20)
                        }
                        .focusable().focusEffectDisabled().focused($galleryFocused)
                        .onKeyPress(.leftArrow) { model.navigate(-1); return .handled }
                        .onKeyPress(.rightArrow) { model.navigate(1); return .handled }
                    }
                } else {
                    ContentUnavailableView("选择或创建一个配方", systemImage: "slider.horizontal.3", description: Text("从左侧开始，把配方与真实的拍摄成果保存在一起。"))
                }
                Divider()
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.status.isEmpty ? "\(model.visibleLinks.count) 张样片 · 仅保存在本机" : model.status).lineLimit(1)
                    Spacer()
                    if !model.results.isEmpty { Button("导入记录") { model.showResults = true }.buttonStyle(.link) }
                }.font(.caption).foregroundStyle(.secondary).padding(10)
                if model.busy && model.progress > 0 { ProgressView(value: model.progress).progressViewStyle(.linear) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard model.library != nil, !model.busy else { return false }
                model.importPhotos(urls); return true
            }
            .navigationSplitViewColumnWidth(min: 410, ideal: 620)
        } detail: {
            if let link = model.currentLink, let photo = model.photo(link), let library = model.library {
                PhotoDetail(photo: photo, link: link, root: library.root, version: model.versions.first { $0.id == link.versionID }, onMove: { moveLink = link }, onRemove: { removeLink = link })
                    .environmentObject(model)
            } else if let version = model.version {
                ScrollView { RecipeDetails(version: version, recipe: model.recipe).padding(20) }
            } else {
                ContentUnavailableView("配方与照片详情", systemImage: "sidebar.right", description: Text("选择一个版本查看配方，或选择样片查看实际拍摄参数。"))
            }
        }
        .onChange(of: model.selectedRecipe) { _, _ in model.selectRecipe() }
        .onChange(of: model.selectedVersion) { _, _ in model.selectedLink = nil }
        .onChange(of: model.showArchived) { _, _ in model.selectedRecipe = nil }
        .navigationTitle(model.recipe?.name ?? "FujiFrame")
    }
    func galleryHeader(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.name).font(.title2.bold())
                    Text(recipe.summary.isEmpty ? "收藏配方的每一种光影" : recipe.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Menu {
                    Button("编辑配方…") { draft = EditorDraft(recipe: recipe, version: model.version ?? model.recipeVersions.first, isNew: false) }
                    Button("复制为新配方…") {
                        var copy = recipe; copy.id = UUID().uuidString; copy.name += " 副本"; copy.archived = false
                        draft = EditorDraft(recipe: copy, version: model.version ?? model.recipeVersions.first, isNew: true)
                    }
                    Button(recipe.archived ? "取消归档" : "归档配方") { model.archive(recipe) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 28).disabled(model.busy)
                Button { model.choosePhotos(fixedTarget: model.selectedVersion) } label: { Label("导入到此版本", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(model.version == nil || model.busy)
            }
            HStack {
                Picker("版本", selection: $model.selectedVersion) {
                    Text("全部版本").tag("")
                    ForEach(model.recipeVersions) { v in Text("v\(v.number)\(v.id == model.recipeVersions.first?.id ? " · 最新" : "")").tag(v.id) }
                }.frame(maxWidth: 180)
                Spacer()
                Toggle("按拍摄日期", isOn: $model.filterDates).toggleStyle(.checkbox).font(.caption)
            }
            if model.filterDates {
                HStack {
                    DatePicker("从", selection: $model.dateFrom, in: ...model.dateTo, displayedComponents: .date)
                    DatePicker("至", selection: $model.dateTo, in: model.dateFrom..., displayedComponents: .date)
                }.font(.caption)
            }
        }.padding(20)
    }
    var importReport: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入记录").font(.title2.bold())
            Text("\(model.results.count) 个文件 · \(model.results.filter(\.failed).count) 个失败").foregroundStyle(.secondary)
            List(model.results) { result in
                HStack(alignment: .top) {
                    Image(systemName: result.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(result.failed ? .orange : .green)
                    VStack(alignment: .leading, spacing: 4) { Text(result.filename); Text(result.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(.vertical, 4)
            }
            HStack { Spacer(); Button("完成") { model.showResults = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620, height: 460)
    }
}

struct PhotoCard: View {
    let photo: Photo
    let link: PhotoLink
    let library: PhotoLibrary
    let selected: Bool
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5))
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(link.filename).font(.callout.weight(.medium)).lineLimit(1)
            Text("\(photo.metadata.rows[0].1)  ·  \(photo.metadata.shutterText)  ·  ISO \(photo.metadata.iso.map(String.init) ?? "—")")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(9).background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
            .task(id: photo.id) {
                do { let url = try await library.thumbnail(for: photo); image = NSImage(contentsOf: url); failed = image == nil }
                catch { failed = true }
            }
    }
}

struct RecipeDetails: View {
    let version: RecipeVersion
    let recipe: Recipe?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("配方记录 · v\(version.number)", systemImage: "slider.horizontal.3").font(.headline)
            Text("手动记录的预设，不代表照片的实际曝光设置。").font(.caption).foregroundStyle(.secondary)
            if let recipe, !recipe.source.isEmpty, let url = URL(string: recipe.source) { Link("查看配方来源 ↗", destination: url).font(.caption) }
            detail("相机", "FUJIFILM X-T5")
            detail("固件", version.firmware.isEmpty ? "未记录" : version.firmware)
            detail("创建时间", version.created.formatted(date: .abbreviated, time: .shortened))
            if !version.note.isEmpty { Text(version.note).font(.callout).foregroundStyle(.secondary) }
            Divider()
            ForEach(XT5.fields) { field in
                detail(field.label, XT5.displayValue(field.id, values: version.parameters))
            }
            Divider()
            Text("曝光建议").font(.headline)
            Text(version.exposureAdvice.isEmpty ? "未记录" : version.exposureAdvice).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }
    func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(minLength: 10); Text(value).multilineTextAlignment(.trailing) }.font(.callout)
    }
}

struct PhotoDetail: View {
    @EnvironmentObject var model: AppModel
    let photo: Photo
    let link: PhotoLink
    let root: URL
    let version: RecipeVersion?
    let onMove: () -> Void
    let onRemove: () -> Void
    @State private var fullScreen = false
    @FocusState private var viewerFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("拍摄详情").font(.title2.bold()); Spacer(); Button { fullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("放大查看") }
                PhotoViewer(url: root.appendingPathComponent(photo.relativePath)).frame(height: 240)
                Text(link.filename).font(.headline).textSelection(.enabled)
                VStack(spacing: 12) {
                    ForEach(photo.metadata.rows, id: \.0) { row in
                        HStack(alignment: .top) { Text(row.0).foregroundStyle(.secondary); Spacer(); Text(row.1).multilineTextAlignment(.trailing) }.font(.callout)
                    }
                }.textSelection(.enabled)
                HStack {
                    Button("纠正版本…", action: onMove)
                    Button("移除…", role: .destructive, action: onRemove)
                }.disabled(model.busy)
                Divider()
                if let version { RecipeDetails(version: version, recipe: model.recipe) }
            }.padding(20)
        }
        .sheet(isPresented: $fullScreen) {
            VStack(spacing: 12) {
                HStack {
                    Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }
                    Text(model.currentLink?.filename ?? link.filename).font(.headline)
                    Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }
                    Spacer(); Button("关闭") { fullScreen = false }.keyboardShortcut(.cancelAction)
                }.padding([.top, .horizontal], 18)
                if let current = model.currentLink, let selected = model.photo(current) {
                    PhotoViewer(url: root.appendingPathComponent(selected.relativePath)).padding([.horizontal, .bottom], 18)
                }
            }.frame(minWidth: 900, idealWidth: 1100, minHeight: 650, idealHeight: 780)
                .focusable().focusEffectDisabled().focused($viewerFocused)
                .onAppear { viewerFocused = true }
                .onKeyPress(.leftArrow) { model.navigate(-1); return .handled }
                .onKeyPress(.rightArrow) { model.navigate(1); return .handled }
        }
    }
}

struct PhotoViewer: View {
    let url: URL
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @State private var failed = false
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                if let image {
                    let ratio = min(geo.size.width / max(image.size.width, 1), geo.size.height / max(image.size.height, 1))
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable()
                            .frame(width: image.size.width * ratio * zoom, height: image.size.height * ratio * zoom)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }.background(Color.black.opacity(0.92))
                } else if failed {
                    ContentUnavailableView("无法读取原图", systemImage: "photo.badge.exclamationmark", description: Text("请检查资料库文件是否存在。"))
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("适应窗口") { zoom = 1 }
                Slider(value: $zoom, in: 1...6).frame(maxWidth: 160)
                Text(String(format: "%.1f×", zoom)).monospacedDigit().font(.caption)
            }.controlSize(.small)
        }.task(id: url) {
            image = nil; failed = false; zoom = 1
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:)); failed = image == nil
        }
    }
}

struct MoveSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let link: PhotoLink
    @State private var target = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("纠正样片所属版本").font(.title2.bold())
            Text(link.filename).foregroundStyle(.secondary)
            Picker("目标版本", selection: $target) {
                Text("请选择").tag("")
                ForEach(model.versions) { v in
                    Text("\(model.recipes.first { $0.id == v.recipeID }?.name ?? "") · v\(v.number)").tag(v.id)
                }
            }
            Text("目标版本已有同一照片时合并关联，不会复制原图。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { dismiss() }; Spacer(); Button("移动") { Task { if await model.move(link, to: target) { dismiss() } } }.disabled(target.isEmpty || target == link.versionID || model.busy).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 500)
    }
}
