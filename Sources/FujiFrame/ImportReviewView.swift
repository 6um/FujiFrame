import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

struct ImportReviewView: View {
    @ObservedObject var session: ImportReviewController
    @State private var selection: Set<UUID> = []
    @State private var filter = "全部"
    @State private var comparisonTarget = ""
    private let filters = ["全部", "已匹配", "待处理", "已排除", "已完成"]
    var displayed: [ImportReviewItem] {
        session.items.filter { item in
            switch filter {
            case "已匹配": return item.ready && item.importError == nil
            case "待处理": return !item.completed && !item.excluded && (item.needsAction || item.importError != nil)
            case "已排除": return item.excluded
            case "已完成": return item.completed
            default: return true
            }
        }
    }
    var selected: ImportReviewItem? { session.items.first { selection.contains($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            header
            controls
            Divider()
            HSplitView {
                photoList
                details
            }
            Divider()
            footer
        }
        .frame(width: 1020, height: 740)
        .interactiveDismissDisabled()
        .onChange(of: selection) { _, _ in comparisonTarget = "" }
        .onChange(of: filter) { _, _ in selection = [] }
        .alert("无法完成操作", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("好") { session.error = nil }
        } message: { Text(session.error ?? "") }
    }
    private var header: some View {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认照片与配方").font(.title2.bold())
                    Text("自动匹配仅比较未归档配方的最新版本。排除照片不会删除源文件。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(session.readyCount) 张可导入 · \(session.unresolvedCount) 张待处理").font(.callout.monospacedDigit())
            }.padding(20)
    }
    private var controls: some View {
            HStack {
                Picker("显示", selection: $filter) { ForEach(filters, id: \.self) { Text($0).tag($0) } }.frame(width: 170)
                Text("已选 \(selection.count) 张").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("批量分配…") {
                    Button("清除分配") { session.assign(selection, target: nil) }
                    Divider()
                    ForEach(session.versions) { v in Button(session.label(v.id)) { session.assign(selection, target: v.id) } }
                }.disabled(selection.isEmpty || !session.canEdit)
                Button("排除") { session.exclude(selection, value: true) }.disabled(selection.isEmpty || !session.canEdit)
                Button("恢复") { session.exclude(selection, value: false) }.disabled(selection.isEmpty || !session.canEdit)
                Button("重新分析") { session.reanalyze(selection) }.disabled(selection.isEmpty || !session.canEdit)
            }.padding(.horizontal, 20).padding(.bottom, 12)
    }
    private var photoList: some View {
                List(selection: $selection) {
                    ForEach(displayed) { item in
                        HStack(spacing: 12) {
                            ReviewThumbnail(url: item.preview).frame(width: 92, height: 66)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.source.lastPathComponent).font(.headline).lineLimit(1)
                                Text(session.label(item.targetVersionID)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(item.status).font(.caption.weight(.medium)).foregroundStyle(item.excluded ? Color.secondary : item.ready ? Color.green : Color.orange)
                            }
                            Spacer(minLength: 0)
                            if item.completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }.padding(.vertical, 4).opacity(item.excluded ? 0.5 : 1).tag(item.id)
                    }
                }.frame(minWidth: 340, idealWidth: 420)
    }
    private var details: some View {
                ScrollView {
                    if let item = selected {
                        VStack(alignment: .leading, spacing: 16) {
                            ReviewThumbnail(url: item.preview).frame(height: 170).frame(maxWidth: .infinity)
                            Text(item.source.lastPathComponent).font(.headline).textSelection(.enabled)
                            Text(item.source.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Picker("导入到", selection: Binding(get: { item.targetVersionID ?? "" }, set: { session.assign([item.id], target: $0.isEmpty ? nil : $0) })) {
                                Text("未分配").tag("")
                                ForEach(session.versions) { v in Text(session.label(v.id)).tag(v.id) }
                            }.disabled(!session.canEdit || item.completed)
                            Text(item.suggestion.reason).font(.callout).foregroundStyle(.secondary)
                            if let failure = item.analysisError ?? item.importError { Label(failure, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                            ForEach(item.settings.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            if !item.suggestion.candidates.isEmpty {
                                Text("相同胶片模拟的候选").font(.headline)
                                ForEach(item.suggestion.candidates) { candidate in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Button(session.label(candidate.versionID)) { comparisonTarget = candidate.versionID }.buttonStyle(.link)
                                        Text("一致 \(candidate.matches) · 不同 \(candidate.conflicts) · 无法读取 \(candidate.missing)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Divider()
                            comparison(item)
                        }.padding(20)
                    } else {
                        ContentUnavailableView("选择照片审核", systemImage: "checklist", description: Text("可使用 Shift 或 Command 多选照片，批量指定配方或排除。"))
                            .frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }.frame(minWidth: 420, idealWidth: 500)
    }
    @ViewBuilder private var footer: some View {
            if session.processing || session.committing { ProgressView(value: session.progress).progressViewStyle(.linear) }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.message).font(.caption).lineLimit(2)
                    if session.unresolvedCount > 0 { Text("请给待处理照片指定配方，或排除它们。").font(.caption).foregroundStyle(.orange) }
                }
                Spacer()
                Button(session.items.contains(where: \.completed) ? "结束审核" : "取消") { session.cancel() }
                    .disabled(session.committing || session.cancelling).keyboardShortcut(.cancelAction)
                Button("确认导入 \(session.readyCount) 张") { session.confirm() }.buttonStyle(.borderedProminent)
                    .disabled(!session.canConfirm).keyboardShortcut(.defaultAction)
            }.padding(18)
    }
    @ViewBuilder func comparison(_ item: ImportReviewItem) -> some View {
        let target = comparisonTarget.isEmpty ? (item.targetVersionID ?? item.suggestion.candidates.first?.versionID) : comparisonTarget
        let version = session.versions.first { $0.id == target }
        let expected = version.map { XT5.normalized($0.parameters) } ?? [:]
        VStack(alignment: .leading, spacing: 12) {
            Text(version == nil ? "照片中可读取的参数" : "参数比较：\(session.label(target))").font(.headline)
            HStack { Text("参数"); Spacer(); Text("照片 / 配方") }.font(.caption).foregroundStyle(.secondary)
            ForEach(XT5.fields.filter { item.settings.values[$0.id] != nil || expected[$0.id] != nil }) { field in
                let detected = item.settings.values[field.id]
                let desired = expected[field.id]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(field.label).font(.callout)
                        Spacer()
                        Text(desired == nil ? "未设约束" : detected == nil ? "无法读取" : detected == desired ? "一致" : "不同")
                            .font(.caption).foregroundStyle(desired == nil ? Color.secondary : detected == desired ? .green : .orange)
                    }
                    Text("\(detected ?? "无法读取")  /  \(desired ?? "未记录")").font(.caption).foregroundStyle(.secondary)
                }
            }
            if item.settings.values.isEmpty && expected.isEmpty { Text("未读取到可比较的配方参数，可以手动分配。").foregroundStyle(.secondary) }
        }
    }
}
private struct ReviewThumbnail: View {
    let url: URL?
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5))
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: url) { image = url.flatMap { NSImage(contentsOf: $0) } }
    }
}
