# macstatus

<img src="assets/logo.png" alt="macstatus" width="116" align="right"/>

原生 macOS 菜单栏（menu bar）系统监控小工具。在状态栏实时显示三项指标：

<img src="assets/screenshot.png" alt="menu bar 预览" width="436"/>

| 指标 | 含义 | 说明 |
| --- | --- | --- |
| `CPU` | CPU 占用百分比 | 已使用（user + system + nice）/ 总时间，与 `top` 的 busy 口径一致 |
| `MEM` | 内存占用百分比 | 已用 = App 内存 + 联动(wired) + 压缩，与「活动监视器」口径一致 |
| `DISK` | 磁盘**剩余**百分比 | 真实可用空间 / 总容量，与 `df` 一致（不含可清除空间） |

等宽数字不抖动，超阈值自动变色（上图：MEM 81% 橙、DISK 8% 红）。

- CPU / 内存 ≥ 75% 显示橙色，≥ 90% 显示红色。
- 磁盘剩余 ≤ 20% 显示橙色，≤ 10% 显示红色。
- 点击菜单栏图标可看到带具体数值（GB）的下拉详情。
- 可切换刷新间隔（1/2/3/5 秒），选择会被记住（下次启动沿用）。
- 「开机自动启动」开关（基于 `SMAppService`，需从打包后的 `.app` 启动）。
- 鼠标悬停状态栏文字可看到完整数值提示。

## 环境要求

- macOS 13 及以上
- Swift 6 工具链（随 Xcode 提供）

## 开发运行

```bash
swift run                 # 直接以菜单栏程序运行（Ctrl-C 退出）
swift run macstatus --once  # 诊断模式：采样一次打印到终端后退出
```

## 打包为 .app

```bash
./scripts/build_app.sh    # 产物：dist/macstatus.app
open dist/macstatus.app   # 启动（无 Dock 图标，仅菜单栏）
```

如需开机自启：把 `dist/macstatus.app` 拖入「系统设置 → 通用 → 登录项」，或用菜单里的「开机自动启动」开关。

> 应用为本地 ad-hoc 签名、未经 Apple 公证。从网络下载的版本首次打开若被 Gatekeeper 拦截，右键 →「打开」一次即可，或执行 `xattr -dr com.apple.quarantine macstatus.app`。

图标由 `swift scripts/make_icon.swift` 渲染各尺寸 PNG，再用 `iconutil` 合成 `assets/AppIcon.icns`。

## 指标实现

- **CPU** — `host_statistics(HOST_CPU_LOAD_INFO)`，对两次采样的 tick 差值计算占用率。
- **内存** — `host_statistics64(HOST_VM_INFO64)`，`已用 = (internal - purgeable + wired + compressed) × 页大小`。
- **磁盘** — `statfs("/")`，`剩余 = f_bavail × f_bsize / (f_blocks × f_bsize)`。

## 项目结构

```
Sources/macstatus/
  main.swift            # 入口；accessory 激活策略 + --once 诊断模式
  SystemMonitor.swift   # CPU / 内存 / 磁盘 采样
  AppDelegate.swift     # NSStatusItem、定时刷新、下拉菜单、开机自启
scripts/build_app.sh    # 编译并打包为 .app（含图标）
scripts/make_icon.swift # 渲染 .icns 图标与 logo.png
assets/                 # AppIcon.icns、logo.png、screenshot.png
```

## 许可

[MIT](LICENSE) © 2026 [uk0](https://github.com/uk0)

## 作者

[github.com/uk0](https://github.com/uk0)
