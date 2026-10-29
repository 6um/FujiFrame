import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FujiFrameApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("FujiFrame", id: "main") {
            ContentView().environmentObject(model)
                .frame(minWidth: 1060, minHeight: 700)
                .task { model.startup() }
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建资料库…") { model.chooseLibrary(create: true) }.disabled(model.busy)
                Button("打开资料库…") { model.chooseLibrary(create: false) }.keyboardShortcut("o").disabled(model.busy)
                Divider()
                Button("智能导入 JPEG…") { model.choosePhotos() }.keyboardShortcut("i").disabled(model.busy || model.library == nil)
                Button("备份资料库…") { model.backup() }.disabled(model.busy || model.library == nil)
                Button("从备份恢复…") { model.restore() }.disabled(model.busy)
            }
        }
    }
}
