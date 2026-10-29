# 开发与验证记录

[返回项目首页](../README.md)

以下命令均在仓库根目录运行。验证记录对应 2026-10-29 的开发环境，并非所有 Mac 的兼容性保证。

## 构建与工程

要求 macOS 14+、Apple Silicon，以及可用的 Swift 5.9+ / Xcode 工具链。当前构建实测：macOS 26.3.1、Swift 6.2.4、arm64。

```bash
./scripts/test.sh
./scripts/build-app.sh
open build/FujiFrame.app
```

构建脚本默认使用 Swift Package 生成 Release 可执行文件并封装为 `.app`，进行本机 ad-hoc 签名。无需 Apple 开发者账号。它没有 Developer ID 公证；当前交付面向这台 Mac 本地使用。

也提供 `FujiFrame.xcodeproj`，可直接在 Xcode 打开。Xcode 完整安装时，可执行：

```bash
./scripts/build-app.sh --xcode
```

本机 `xcodebuild` 加载插件时报告缺少 `CoreSimulator.framework`，因此当前 `.app` 由 Swift Package 构建；Xcode 工程通过 plist 语法验证，尚未在本机完成 Xcode 路线构建。无须为使用已生成的应用修复该组件。

新增 Swift 源文件后运行 `python3 scripts/generate-project.py` 更新 Xcode 文件列表。`Package.swift` 自动发现 Sources 下文件。

- `Sources/FujiFrameCore`：字段校验、数据模型、SQLite、导入、元数据及备份。
- `Sources/FujiFrame`：原生 SwiftUI 界面与应用状态。
- `Tests/FujiFrameCoreTests`：使用生成 JPEG 的自动化测试，不依赖真实照片。
- `scripts/MakeQAFixtures.swift`：可复现的 UI 测试资料库生成器。

## 当前验证与边界

30 项自动测试全部通过，覆盖版本隔离、重命名/归档、去重、纠正关联、同名不同文件、EXIF 缺失及旋转、损坏/不存在的文件、备份恢复、备份损坏、锁、资料库移动和暂存恢复。界面已实测启动、打开/关闭资料库、新建配方、8 张 JPEG 批量导入、网格与曝光详情、文件名搜索、竖拍预览、放大、网格及大图方向键切换；重启后配方和照片仍完整。

智能导入已通过桌面端到端验收：四张合成 JPEG 中，两张自动匹配到不同配方，一张手动分配至历史版本，一张排除；恢复排除会重新阻止确认，最终三张入库，数据库中的版本关联正确。自动化测试另覆盖严格匹配、歧义与缺失字段、畸形 MakerNotes、审核取消无写入、源文件变化和部分失败后的重新分析重试。本次验收生成的测试资料位于本机 `build/smart-qa`，未写入个人资料库；构建产物和测试资料库均不包含在仓库中。复现方法见 [参数读取说明](FUJI_METADATA.md#测试与复现)。

尚未拿到真实 X-T5 直出 JPEG，尚未实测磁盘写满或超大规模照片库。当前不支持 RAF、HEIF、从照片新建配方、图像编辑或云同步。

本机另有 `build/qa/QA Library` 合成样片资料库，由 `scripts/MakeQAFixtures.swift` 生成。它不随源码下载提供；正式使用请创建自己的资料库。
