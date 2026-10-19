# WLoc Native · 常用定位

**无需自建后台。** 在 iPhone 内粘贴苹果地图、高德、Google Maps 分享链接，或使用 App 地图搜索 / 选点，将位置收藏后点一下写入 Surge 本机。

[App 源码与 Actions 构建](https://github.com/JavaWeh/wloc-ios/actions/workflows/build-ipa.yml) · [配套 Surge 模块](https://raw.githubusercontent.com/JavaWeh/wloc-ios/main/Surge/WLoc-Native.sgmodule) · [上游参考 Fork](https://github.com/JavaWeh/ios-location-spoofer)

## v2 工作方式

~~~text
地图链接 / App 内地图
        ↓
本机解析、坐标系换算、确认、收藏
        ↓
Surge 本机请求脚本 → 本机 persistentStore
        ↓
WLOC 响应脚本 → 后续系统网络定位
~~~

不需要服务器、Cloudflare Worker、选点服务地址或后台 token。地图瓦片、地点搜索和短链展开仍需要访问相应地图提供方。带坐标的长链接和纯经纬度可以在本机解析。

原版 location-picker 的 Node 服务没有作为常驻服务器塞进 IPA：普通 iOS App 进入后台后不能可靠地持续提供 HTTP 服务。本版把选点、搜索、解析和收藏做成原生界面，把需要持续读取的坐标交给本来就在运行的 Surge。关闭 App 后已保存的 Surge 配置仍有效。

最低 iOS 16，中文 SwiftUI 界面，支持 iPhone / iPad、深色模式。实际定位能力仍取决于 Surge、MITM、WLOC、iOS 缓存和 GPS 条件。App 无法清除 locationd 缓存或自行重启系统定位服务。

## 首次配对（仅一次）

1. 安装新版 IPA，在 App 中打开 **Surge 本机配对**，复制自动生成的配对密钥。
2. Surge → 模块 → 安装新模块，粘贴：
   ~~~text
   https://raw.githubusercontent.com/JavaWeh/wloc-ios/main/Surge/WLoc-Native.sgmodule
   ~~~
3. 在新模块参数中把 **key** 填成 App 复制的密钥。启用本模块，**停用其他 WLOC 响应改写模块**，避免同一请求被多份脚本处理。
4. 保留现有 MITM 设置，确认 Surge CA 已安装并在 iOS 中完全信任。新模块包含相应定位域名。
5. 返回 App，点 **验证 Surge 本机连接**。配对密钥保存在本机钥匙串。

配对 key 是本机模块的访问密钥，由 App 自己生成；不需要向任何网站注册，也不要把它提交到公开仓库。卸载 App 或移除配对不会自动关闭 Surge 中的设置；需要恢复时先点 App 首页的“关闭虚拟定位”。

首次安装且未提交坐标时，配套模块默认不改写定位；关闭后同样放行原始响应，不回退到预设坐标。

## 标记与切换

- 点首页“粘贴地图链接 / App 地图选点”，粘贴地图分享的整段文字或链接，点解析。
- 解析后核对名称、坐标、原始坐标系和地图预览，点“收藏”。收藏只保存到手机。
- 也可以打开 App 内地图搜索地点，或拖动地图把准星放在目标上，然后收藏。
- 回首页点选收藏，才将位置写入 Surge。按你原先验证成功的生效步骤刷新系统定位，并打开系统地图确认。
- 支持编辑、删除、排序、收藏当前 Surge 坐标，或直接手填 WGS-84 坐标。切换地点不需要重新打开选点网页。

### 链接支持与坐标系

| 来源 | 当前识别格式 |
| --- | --- |
| 苹果地图 | coordinate、ll 参数，含坐标的新旧分享链接 |
| 高德 | position / lnglat（经度,纬度）、p / q 分享参数、iosamap lat/lon |
| Google Maps | query / q / destination 经纬度、!3d / !4d 地点坐标、@ 地图中心 |
| 短链接 | 限定地图域名内的 HTTPS 重定向、规范链接和部分页面跳转，最多 5 次 |
| 手工 | 纬度,经度；支持负数、0、英文或中文逗号 |

**不会保证任意地图短链都可解析。** 只有地点 ID、反爬页面、需要登录或 JavaScript 才能取得坐标的分享页，可能无法展开。失败时可改用 App 地图搜索 / 选点或手填坐标。

Google 的地点针脚坐标优先于地图视口中心；只有视口中心时会明确提示，含多个地点的路线不会猜选一个。不会从 HTML 中任意两个小数猜测经纬度。

最终保存和提交均为 WGS-84；支持 WGS-84、GCJ-02、BD-09 转换。高德默认 GCJ-02；国内苹果地图按 GCJ-02 提示核对；港澳台、境外和 Google 国内道路数据请对照原地图手动选择坐标系。使用矩形区域作默认判断，不能代替你对数据来源的确认。

## 本机控制实现

App 首先对 Surge 拦截路径发起不含密钥、坐标的 health 请求，检查专属协议标记，再发送配对密钥和坐标。控制地址由 App 固定，不需要输入服务地址。

- 控制路径：gs-loc.apple.com/wloc-native/v1/health、config、disable。
- 控制脚本：Surge/wloc-control.js，直接返回 JSON，不通过远端选点后台。
- 存储键：wloc_native_target_v2。
- 改写脚本：Surge/location-spoofer-local.js，从本机存储读取；缺少或损坏配置时不改写。
- 需要配套模块、Surge VPN 和 MITM 启用；原版其他选点页 / 模块的存储格式与本版不同。

本项目暂未在用户设备完成真实的 Surge 配对与定位验证。CI 的测试会模拟 Surge 环境并使用真实二进制 WLOC 测试数据验证“写入 → 改写 → 关闭后放行”。

## 没有 Mac：使用 GitHub Actions 构建 IPA

1. 打开仓库 Actions → **Build unsigned IPA** → **Run workflow**。
2. 等成功后，从该次运行底部 Artifacts 下载 **WLoc-unsigned-ipa**。
3. 解压得到 WLoc-unsigned.ipa，在 Windows 用自己的签名工具或 [Sideloadly](https://sideloadly.io/) 签名安装。
4. 安装后按上面的“首次配对”步骤操作。保持原 Bundle ID 和签名团队有助于保留收藏和钥匙串。

构建不需要 Apple 账号、签名证书、配对 key 或地图 API key。未签名 IPA 需自签后才能安装。Actions 产物保留 14 天，过期后重新构建。

Mac 本地也可运行：
~~~bash
bash scripts/build-ipa.sh
~~~

输出 build/WLoc-unsigned.ipa。工程无第三方 iOS 依赖；MapKit 使用系统框架。

## 测试与开源

- Swift 核心测试：地图参数顺序、针脚与视口优先级、非法链接、短链规范 URL、坐标换算、配对探测、写入与关闭协议。
- Node 集成测试：Surge 控制脚本鉴权、错误配置、持久化失败、真实 WLOC 二进制响应改写、未配置与关闭后的透传。
- Python 测试：IPA 结构、可执行权限及模拟器产物拒绝。
- 本机测试不能代替真机安装和地图效果验证。

许可证为 **AGPL-3.0-or-later**。本版已包含修改后的上游 WLOC 脚本及许可证；作者与源码来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

参考协议：[Surge HTTP request 脚本](https://manual.nssurge.com/scripting/http-request.html)、[持久化存储](https://manual.nssurge.com/scripting/api.html)、[高德 URI](https://lbs.amap.com/api/uri-api/guide/mobile-web/point)、[Google Maps URL](https://developers.google.com/maps/documentation/urls/get-started)、[Apple 后台执行限制](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)。

## v2 构建验证

[v2 云端构建 #2](https://github.com/JavaWeh/wloc-ios/actions/runs/39223050972) 已成功：17 项 Swift 测试零失败，Surge 控制与真实 WLOC 二进制集成测试通过，完成 iPhoneOS arm64 编译与未签名 IPA 打包。

[下载 v2 构建产物](https://github.com/JavaWeh/wloc-ios/actions/runs/39223050972/artifacts/12172068219)（需登录 GitHub；产物保留 14 天，过期后重新构建）。IPA 版本 2.0.0，最低 iOS 16；IPA 本身的 SHA-256 为 `69d5c9aa08ad86187f2e39420068c99ed00d66cde8f05c49969c21127ad857a2`。

上述是编译和协议验证，不代表已在具体手机上完成 Surge 配对、地图坐标系和系统定位效果的实测。安装后请按首次配对步骤验证。
