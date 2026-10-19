# WLoc Native · 常用定位

无需自建后台。在 iPhone 内解析苹果地图、高德、Google Maps 分享链接，或使用原生地图搜索 / 选点，保存收藏后点一下写入当前代理工具。

**2.1.0：增加五端配置生成、独立配对及快捷安装。** App 自动生成含本机密钥的专属配置，无需手动修改脚本。快捷下载及五端真实定位效果尚待真机验证，界面明确标注实验状态；协议模拟通过不等同于真机支持认证。

[Actions 构建](https://github.com/JavaWeh/wloc-ios/actions/workflows/build-ipa.yml) · [审计与验证记录](AUDIT.md) · [上游参考 Fork](https://github.com/JavaWeh/ios-location-spoofer)

## 安装与配对

1. 自签安装 IPA，在 App 齿轮页选择当前使用的工具。
2. Surge、Loon、Stash 优先尝试“快捷安装”；Quantumult X、Shadowrocket 优先“导出专属配置文件”。若分享列表中没有该工具，先保存到“文件”，再按页面说明在目标工具导入本地文件。
3. 确认安装并启用组件，停用其他 WLOC 定位模块。保留已有 MITM 证书；新工具的证书仍须自行安装，并在系统设置中开启完全信任。
4. 返回 WLoc，自动或手动点“验证本机连接”。只有接口和工具身份验证通过才完成配对。打开目标 App 或下载文件不代表已经完成安装。
5. 回首页点选收藏，写入目标坐标，再按你原先验证成功的步骤刷新系统定位并打开地图确认。

| 工具 | 专属文件 | 导入入口 | 当前验证状态 |
| --- | --- | --- | --- |
| Surge | `.sgmodule` | 安装模块 | 协议与二进制模拟；快捷导入、重启保留、真机效果待验证 |
| Loon | `.lnplugin` | 导入插件 | 同上；包含请求准备脚本 |
| Stash | `.stoverride` | 安装覆写 | 同上 |
| Quantumult X | `.snippet` | 本地重写；实验快捷追加资源 | 同上；建议本地文件，避免临时地址成为长期远程引用 |
| Shadowrocket | `.sgmodule` | 本地模块；实验快捷安装 | 同上；快捷入口兼容性待实测 |

专属文件含密钥，请只用于自己的目标工具，不要上传、公开或分享。密钥分别保存在 App 钥匙串；收藏共用。切换工具会清除界面中的旧连接状态，只有当前工具被启用并验证后才能确认其配置。不会自动替换订阅、节点或主配置，也不会自动启动多个 VPN。

## 快捷安装为什么仍有备用方式

App 临时在 `127.0.0.1` 的随机端口提供本次配置下载，路径使用独立随机令牌，最长 120 秒；iOS 可以提前结束后台时间。服务不监听局域网、不提供目录、不运行选点后台，也不提供运行时坐标或脚本。

导入失败时返回 App 重新开始，或改用文件导入。若目标工具把临时地址保留为远程资源，请改用本地导入，不要依赖该地址后续更新。安装完成后，脚本由构建对应的固定 Git 提交下载，坐标保存在代理工具内部，关闭 WLoc 不影响已保存配置。

所有平台的“文件已交付”“已验证本机连接”“真机定位有效”是不同状态。首次使用请额外测试目标工具重启后配置是否保留；有问题时使用本地文件导入并反馈工具版本及不含密钥的错误信息。

## 旧版 Surge 用户

升级 App 保留原 Bundle ID、签名团队、收藏和旧协议配对。旧版 `Surge/WLoc-Native.sgmodule`、v1 控制路径及 `wloc-native-v2` 标记继续可用，无需强制重新安装模块。配对页也保留“连接已有旧版 Surge 模块”。

若选择升级安装新组件，必须停用旧 WLOC 模块。准备新安装文件不会立刻覆盖已验证的旧配对，只有新连接验证成功才替换。

旧模块报“模块头部的参数声明格式错误：key:”时，使用已修复的[旧版模块](https://raw.githubusercontent.com/JavaWeh/wloc-ios/main/Surge/WLoc-Native.sgmodule)，其默认参数为 `SET_KEY_IN_APP`；新专属配置无需该参数表。

移除 App 中的配对不会关闭工具中已保存的坐标；需要恢复时先点首页“关闭虚拟定位”。

## 标记与切换

- 粘贴地图分享文字或完整链接，解析后核对名称、原始坐标系和预览；也可原生地图搜索、拖动准星选点或手填纬度、经度。
- 支持编辑、删除、排序及收藏当前工具的坐标。收藏只保存在本机，点击首页收藏才提交。
- 纯坐标和含坐标长链本机解析；地图搜索、瓦片和短链展开仍需访问地图提供方。
- 最终保存为 WGS-84。原生 MapKit 按 WGS-84 接口处理；高德链接默认 GCJ-02，国内苹果地图链接按 GCJ-02 提示核对，仍可手动选择 WGS-84 / GCJ-02 / BD-09。
- Google 支持数值 query / q / destination、地点数据坐标和带提示的视口中心。不能可靠还原的地点 ID、复杂路线、反爬或依赖 JavaScript 的短链会拒绝或解析失败，不猜测坐标。
- 修改输入清空旧草稿，过期网络结果不能覆盖新选点。短链读取上限 512 KiB，控制响应 64 KiB；定位精度限定 1～1,000,000 米。
- 损坏收藏先保留恢复副本；读取或备份失败时禁止覆盖原文件。

原版 location-picker 的常驻 Node 服务没有塞入 IPA。本版使用原生界面，持续运行的定位改写交给代理工具。App 无法清除 locationd 缓存或控制 GPS 优先级。用户此前确认 iOS 26.4 上游网页方式可用，不代表本版五端均已真机通过。

## 本机协议与安全边界

- 新协议标记 `wloc-native-v3`，健康检查地址 `/wloc-native/v3/health` 不含密钥、坐标，返回工具标识。
- 读写位于 `/wloc-native/v3/<本机密钥>/config`、`disable`；QX 另以 `status` 读取，避免空 body 的请求进入 body 分析脚本。新路径仍在 `https://gs-loc.apple.com` 下，由所选工具本机合成响应。
- 专属配置的匹配规则必须精确包含本机密钥。这是鉴权边界，不能替换为通配密钥；脚本另校验 `X-WLoc-Key` 与路径一致。密钥不通过脚本参数传递，适用于 QX。
- App 检查协议和工具身份后才发送认证请求。不要导出或分享包含完整专属路径的代理请求日志；App 不记录或显示这些 URL。
- 坐标存储键沿用 `wloc_native_target_v2`，每个工具在自己的存储中独立保存；QX 使用 `$prefs`，其他使用 `$persistentStore`。
- 上游 WLOC 核心固定版本并保留署名；五端共用同一份派生核心，QX 适配二进制 `bodyBytes`，Loon 使用准备脚本请求未压缩响应；未配置、关闭或损坏配置时透传。

## 没有 Mac：GitHub Actions 构建

1. Actions → **Build unsigned IPA** → **Run workflow**。
2. 成功后下载 Artifacts 中的 **WLoc-unsigned-ipa**，解压得到 IPA。
3. 在 Windows 用自己的签名工具或 [Sideloadly](https://sideloadly.io/) 签名安装。

构建不需要 Apple 账号、证书、配对密钥或地图 API key。IPA 未签名，必须自签安装。最低 iOS 16，Bundle ID 保持 `com.wloc.quicklocation`；产物保留 14 天，过期后重建。

Mac 本地从已提交的 Git checkout 执行 `bash scripts/build-ipa.sh`；脚本把当前提交固定到 IPA 的脚本版本。也可显式提供 `GITHUB_SHA` 为已公开、包含完整脚本的 40 位提交 SHA。输出 `build/WLoc-unsigned.ipa`。

## 测试与开源

保留原有 27 项 Swift 回归测试，新增配置与链接生成、钥匙串数据模型迁移、独立配对、身份检查、临时下载访问控制和实际回环网络测试。Node 测试逐端验证控制、存储和真实二进制 WLOC 改写，并校验 Swift 实际生成的匹配规则。CI 另检查生成文件可复现、工程、打包与真实 iPhoneOS 编译。

测试及构建结果见 [AUDIT.md](AUDIT.md)。真机验证矩阵均暂标待验证，不把 CI 当作真实导入和定位测试。

[2.1.0 构建已成功](https://github.com/JavaWeh/wloc-ios/actions/runs/39232732356)：40 项 Swift 测试、五端二进制集成与 3 项打包测试通过。[下载未签名 IPA](https://github.com/JavaWeh/wloc-ios/actions/runs/39232732356/artifacts/12178241922)（需登录 GitHub，保留 14 天）。IPA SHA-256：`46683177923029ce39778ce5e5c110e7e39453c08db54cb36d7564cf63f8fb29`。

许可证为 **AGPL-3.0-or-later**，作者与来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

官方接口参考：[Surge 导入](https://manual.nssurge.com/tools/url-scheme.html)、[Loon 导入](https://nsloon.app/docs/Scheme/)、[Stash 导入](https://stash.wiki/faq/url-schema)、[Quantumult X 追加资源](https://github.com/crossutility/Quantumult-X/blob/master/url-scheme.md)、[Apple 后台限制](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app)。
