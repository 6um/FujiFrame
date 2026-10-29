import SwiftUI
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

struct EditorDraft: Identifiable {
    let id = UUID()
    var recipe: Recipe
    var version: RecipeVersion?
    var isNew: Bool
}

struct RecipeEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var recipe: Recipe
    @State var parameters: [String: String]
    @State var firmware: String
    @State var exposure: String
    @State var note = ""
    @State var advanced = false
    let isNew: Bool
    init(draft: EditorDraft) {
        _recipe = State(initialValue: draft.recipe)
        _parameters = State(initialValue: draft.version?.parameters ?? [:])
        _firmware = State(initialValue: draft.version?.firmware ?? "")
        _exposure = State(initialValue: draft.version?.exposureAdvice ?? "")
        isNew = draft.isNew
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "创建配方" : "编辑配方").font(.title2.bold())
                    Text("FUJIFILM X-T5 · 未填写的设置保留为未记录").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section("配方信息") {
                    TextField("名称", text: $recipe.name)
                    TextField("简介", text: $recipe.summary, axis: .vertical).lineLimit(2...4)
                    TextField("来源链接", text: $recipe.source)
                    TextField("相机固件版本（可选）", text: $firmware)
                    TextField("曝光建议", text: $exposure, axis: .vertical).lineLimit(2...3)
                }
                Section("胶片配方") {
                    ForEach(XT5.fields.filter { !$0.advanced }) { field in parameter(field) }
                    if parameters["film"] == "REALA ACE" {
                        Text("REALA ACE 的可用性取决于相机固件，请以相机菜单为准。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let priority = parameters["drPriority"], priority != "OFF", !priority.isEmpty {
                        Text("已启用动态范围优先级：动态范围、高光和阴影由相机自动控制，这些手动值不会保存。").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("DR200 / 优先级 WEAK 需要 ISO ≥ 250；DR400 / STRONG 需要 ISO ≥ 500。").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("高级参数", isExpanded: $advanced) {
                    ForEach(XT5.fields.filter(\.advanced)) { field in parameter(field) }
                }
                if !isNew {
                    Section("版本说明") {
                        TextField("此次调整的原因（可选）", text: $note, axis: .vertical).lineLimit(2...4)
                        Text("参数、固件或曝光建议改变时生成新版本。仅修改名称、简介、来源不会创建新版本。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    Task { if await model.save(recipe, parameters: parameters, firmware: firmware, exposure: exposure, note: note) { dismiss() } }
                }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }.padding(20)
        }.frame(width: 650, height: 780)
        .interactiveDismissDisabled(model.busy)
        .alert("无法保存", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    @ViewBuilder func parameter(_ field: ParameterField) -> some View {
        Picker(field.label, selection: Binding(get: { parameters[field.id] ?? "" }, set: { parameters[field.id] = $0 })) {
            Text("未记录").tag("")
            ForEach(field.options, id: \.self) { Text($0).tag($0) }
        }.disabled(XT5.disabled(field.id, values: parameters))
    }
}
