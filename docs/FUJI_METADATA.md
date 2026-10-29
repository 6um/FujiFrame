# X-T5 配方参数读取

`FujiMetadata.swift` 是独立实现的只读 Swift JPEG/EXIF/TIFF 解析器，不运行、不打包 ExifTool。标签编号与编码含义核对自 ExifTool 官方项目 `lib/Image/ExifTool/FujiFilm.pm`（2026-10-29 查看，模块标示版本 2.03）：

- https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/FujiFilm.pm
- https://exiftool.org/TagNames/FujiFilm.html

JPEG 只扫描 SOS 前的标记段；EXIF TIFF 支持两种字节序；富士 MakerNotes 使用其自身的基准偏移和小端目录。解析器检查段长度、目录大小、数量、标签重复、偏移和整数范围，不使用不安全内存读取。对可正常显示但专有元数据损坏的 JPEG，审核仍允许人工指定配方。

## 已实现的转换

| 应用字段 | 标签 / 转换 |
| --- | --- |
| 胶片模拟 | `0x1401 FilmMode`，结合 `0x1003 Saturation`；黑白/ACROS 及滤镜以 Saturation 的专用编码为准 |
| 色彩 | `0x1003` 的已知彩色编码 |
| 白平衡 | `0x1002` 已知模式；不推测未知模式 |
| 白平衡偏移 | `0x100a` 两个有符号值分别除以 20；只接受可整除且结果在 -9…9 的值 |
| 色温 | `0x1005`，仅色温模式，2500…10000 K、10 K 步长 |
| 锐度、高 ISO 降噪 | `0x1001`、`0x100e` 的明确枚举 |
| 清晰度 | `0x100f` 有符号值除以 1000，范围 -5…5 |
| 高光、阴影 | `0x1041`、`0x1040`：负原值 / 16，允许 0.5 步长 |
| 颗粒、彩色效果、FX 蓝色 | `0x1047`、`0x1048`、`0x104e`：0 / 32 / 64 对应 OFF / WEAK / STRONG |
| 颗粒大小 | `0x104c`：16 / 32 对应 SMALL / LARGE |
| 黑白色调 | `0x1049`、`0x104b` 有符号数值；仅黑白模式有效 |
| 镜头优化 | `0x1045`：明确的 0 / 1 |
| 动态范围 | `0x1402` 明确 Auto 或 Standard；Manual 时才使用 `0x1403` 的 100 / 200 / 400 |
| 动态范围优先级 | `0x1443` 的 Auto，或 Fixed 配合 `0x1445` 的 Weak / Strong |

## 保守限制

- 只对通用 EXIF 机型为 `X-T5` 的文件执行自动解析；其他机型可以人工分配。
- 缺失动态范围优先级标签不推断为 OFF；自动动态范围的实际结果不覆盖 AUTO。
- 官方标签表将白平衡 `0x200` 标为 Cloudy，应用现有选项是“阴影”；未用真实样片核实前不把二者视为相同。
- 柔肤、长曝光降噪、色彩空间以及其他未建立可靠转换的字段暂不参与自动读取。若配方填写了这些字段，严格匹配将因缺失信息而保持待处理。
- 未记录的配方字段不构成匹配条件；可比较参数须包含胶片模拟及至少三个其他字段，且全部相同、候选唯一，才自动预选。固件、备注和曝光建议不比较。
- 所有回归用 MakerNotes 是按上述映射构造的合成数据，不构成对真实相机固件输出的验证。

## 测试与复现

`Tests/TestSupport/FujiFixture.swift` 生成独立的 TIFF / MakerNotes 字节流，测试覆盖 EXIF 字节序、黑白模拟、自动设置、缺失信息、越界偏移和截断等。`Tests/FujiFrameAppTests` 测试审核会话，包括取消、批量调整、排除恢复及部分失败后重试。

如需重新生成独立的界面测试资料库（目标应是新的空目录）：

```bash
swiftc -parse-as-library -module-cache-path .build/clang Sources/FujiFrameCore/*.swift Tests/TestSupport/FujiFixture.swift scripts/MakeSmartQAFixtures.swift -lsqlite3 -o .build/make-smart-qa
.build/make-smart-qa "$PWD/build/smart-qa"
```

其中两张 JPEG 可以严格匹配不同的测试配方，另外两张没有富士参数，需要人工选择或排除。此工具不会访问正式资料库。
