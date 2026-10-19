# WLoc 常用定位

给已有 Surge / WLOC 选点服务做的原生 iOS 快捷客户端。添加几个常用地点后，轻点即可提交坐标，无需每次打开网页选点。

常用地点在 App 内添加、编辑和保存。最低部署版本为 iOS 16。界面为中文，支持深色模式和 iPhone / iPad；实际定位能力取决于现有 Surge / WLOC 配置和系统版本。

**没有 Mac 也能构建：** 打开本仓库 [Actions](https://github.com/JavaWeh/wloc-ios/actions/workflows/build-ipa.yml)，运行 **Build unsigned IPA**，成功后下载 `WLoc-unsigned-ipa` 构建产物。解压得到 IPA 后用自己的账号签名安装。

参考服务 Fork：[JavaWeh/ios-location-spoofer](https://github.com/JavaWeh/ios-location-spoofer)。本仓库独立维护原生客户端。

## 当前交付状态

- 已提供 SwiftUI 应用源码、可直接打开的 `WLoc.xcodeproj`、核心接口单元测试、构建脚本及 GitHub Actions 工作流。
- **首次云端构建已成功：** [构建记录 #1](https://github.com/JavaWeh/wloc-ios/actions/runs/39219898365)，Xcode 16.4 / iPhoneOS 18.5 SDK，9 项核心测试零失败，成功生成 iPhoneOS arm64 未签名 IPA。最低 iOS 16；尚未验证具体设备上的安装和定位效果。
- [下载该次 IPA 构建产物](https://github.com/JavaWeh/wloc-ios/actions/runs/39219898365/artifacts/12170947989)（需登录 GitHub，产物保留 14 天；过期后重新运行 Actions）。解压后得到 `WLoc-unsigned.ipa`。
- 源码在 Windows 上开发；本地已通过工程结构与 OpenStep 解析、9 个 Swift 文件的语法解析、工作流 YAML 解析和 3 项打包单元测试。实际编译与核心接口测试由 macOS Actions 运行，结果以对应运行记录为准；尚未完成真机验证。
- GitHub Actions 或 Mac 完成编译后会生成 `WLoc-unsigned.ipa`，再使用你自己的工具签名安装。仅把源码压成 IPA 无法安装。

首次 IPA 的 SHA-256：`3dd50f208d6d102ebc32bc16f1af349477995226a9a825930c6e9bddcf4dd0f4`。这是 IPA 本身的校验值，不是 Actions 外层 ZIP 的校验值。

## 工作方式与前提

```text
App 点选收藏 → 现有选点服务 /set → Surge 的 configUrl → WLOC 响应改写 → iOS 后续定位
```

这是原网页的原生快捷替代界面。**需要原选点服务继续运行，且 Surge 与 App 连接同一个服务、同一个 token。** App 不直接写入其他 App 的文件，也不会启动第二个 VPN。

复用 [ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer) 的 Node / Cloudflare Worker 选点服务协议：

| 操作 | 请求 | 用途 |
| --- | --- | --- |
| 读取配置 | `GET /loc.json?token=…` | 读取服务端坐标和开关 |
| 提交地点 | `POST /set?token=…` | JSON 为 `lat`、`lng`、`horizontalAccuracy`；原服务自动开启虚拟定位 |
| 关闭虚拟定位 | `POST /enable?token=…` | JSON 为 `{"enabled":false}` |

未提交海拔和垂直精度，因此保留服务中的现有设置。支持选点网页链接或 `loc.json` 链接，支持部署在反向代理子路径下，保留附加查询参数。仅接受 HTTPS；拒绝自动重定向。

如果你现在只安装了固定经纬度的 Surge 模块，而没有部署选点服务，需要先配置原仓库的选点服务，并让脚本通过 `configUrl` 读取它。参考项目自带的默认 Surge 模块只有固定参数，不会自动连接任意网页。本 App 的“连接成功”只证明服务可读，不能证明 Surge 已使用该服务。

## 使用

1. 安装并打开 App，进入“服务设置”。
2. 从你现在可用的选点网页复制**完整 HTTPS 地址（含 `?token=…`）**，粘贴到输入框；也可粘贴 Surge 中相同的 `loc.json` 链接。点击“验证并保存连接”。不要把私密 token 提交到代码或发到聊天中。
3. 点击“添加地点”，填名称、**WGS-84 纬度、经度**和水平精度，然后保存。保存只更新本机收藏。
4. 返回首页，轻点地点提交。显示“已保存”表示服务响应确认了目标坐标，**不代表系统定位已即时改变**。
5. 按你在 iOS 26.4 上已经验证成功的步骤刷新系统定位，并打开系统地图确认。Surge / iOS 缓存可能造成延迟，App 无法清除系统缓存或自动重启定位服务。

可以先从原网页选好一个已验证正确的位置，再点击 App 的“刷新服务端配置”→“收藏当前配置坐标”，避免坐标系或手工输入错误。高德、腾讯地图一般使用 GCJ-02，百度地图使用 BD-09，请先转换成 WGS-84；本版不自动转换。

点铅笔编辑；左滑删除；“编辑”可调整顺序。点击“关闭虚拟定位”会让原服务返回 `enabled=false`，仍需在地图确认恢复效果。仅移除本机连接或卸载 App 不会关闭服务端设置。

收藏保存在本机 Documents/places.json（原子写入和文件保护）。服务连接信息保存在本机钥匙串；网络使用无磁盘缓存会话。重新自签时尽量保持相同的 Bundle ID 和签名团队，避免数据或钥匙串访问范围改变。

## Windows 用户：使用 GitHub Actions 生成 IPA

1. 将本项目文件放入你自己的 GitHub 仓库，建议使用私有仓库。**不要上传 `upstream/`、私密选点地址或 token**，不要只上传源码压缩包。
2. 打开仓库的 Actions → **Build unsigned IPA** → **Run workflow**。工作流不需要 Apple 账号、证书或 token。
3. 等待构建成功，在该次运行的 Artifacts 下载 `WLoc-unsigned-ipa`，解压得到 `WLoc-unsigned.ipa`。
4. 使用你已有的 IPA 自签工具，或 [Sideloadly](https://sideloadly.io/) / [AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-use-altstore)，以自己的账号签名安装。按工具指引完成设备信任等安装步骤。

工作流先运行核心测试，再进行真机 arm64 构建并打包。若测试或编译失败，流程不会上传伪造的 IPA，请根据 Actions 日志修复。

## Mac 用户：本地构建

安装完整 Xcode，确认 `xcode-select` 指向 Xcode 的 Developer 目录。在项目根目录运行：

```bash
bash scripts/build-ipa.sh
```

输出：`build/WLoc-unsigned.ipa`。也可以打开 `WLoc.xcodeproj`，在 Signing & Capabilities 选择自己的 Team 和唯一 Bundle ID，连接 iPhone 后直接运行。

工程本身无第三方依赖。`scripts/generate_project.py` 可重新生成工程；仅在新增 / 删除 Swift 源文件时需要执行。图标已包含在资源中，正常构建无需安装 Pillow 或重新生成图标。

## 验证范围

`swift test` 覆盖：网页与配置链接解析、子路径、特殊字符 token、非法坐标、服务协议字段、读写与关闭请求、HTTP 错误、无效响应及保存坐标确认。测试使用模拟 HTTP 响应，不会访问你的服务。Windows 可运行 `python scripts/check_project.py` 检查工程结构。

首次在真机安装后请核对：连接已有服务；新增 / 编辑 / 排序 / 重启 App 后收藏仍在；切换两个不同地点后原网页能读到对应坐标；关闭后网页显示关闭；最后在系统地图中分别确认效果。网页能看到变化而系统地图不变时，应排查 Surge 的 configUrl、刷新周期与系统定位缓存。

## 参考来源

协议核对版本：上游提交 `06feaf2f2279ab966567f946d87ead9461564634`。

- [Node 服务接口](https://github.com/mekos2772/ios-location-spoofer/blob/06feaf2f2279ab966567f946d87ead9461564634/location-picker/server.js)
- [Worker 接口说明](https://github.com/mekos2772/ios-location-spoofer/blob/06feaf2f2279ab966567f946d87ead9461564634/location-picker/worker/README.md)
- [Surge 原始模块](https://github.com/mekos2772/ios-location-spoofer/blob/06feaf2f2279ab966567f946d87ead9461564634/ios-location-spoofer-surge.sgmodule)

上游采用 AGPL-3.0。本项目独立实现 iOS HTTP 客户端，没有打包或复制上游 WLOC 改写脚本、网页或服务端代码；现有服务和 Surge 脚本由你继续使用。若后续把上游源码合并、修改或随应用分发，应保留其许可证及署名并履行相应义务。
