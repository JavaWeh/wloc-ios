# 开源来源与修改说明

WLoc Native v2 以 **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)** 分发，完整许可证见 [LICENSE](LICENSE)。App 内也提供许可证和完整源码入口。

## WLOC 响应解析与改写

- 项目：[mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer)，保留原作者、该项目全部贡献者及其上游研究作者的署名。
- 上游研究：[acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer)。
- 固定版本：`06feaf2f2279ab966567f946d87ead9461564634`，原始文件位于 `Surge/vendor/location-spoofer.upstream.js`。
- 生成文件：`Surge/location-spoofer-local.js`，由 `scripts/build_local_spoofer.py` 生成。
- 修改：读取 `wloc_native_target_v2` 本机持久化值，关闭远程 configUrl 读取；无坐标、配置损坏或 disabled 时放行原始响应。
- 原始源文件 SHA-256（统一 LF 换行）：`36e078178ac40ef6dbd952deaaabfe257e0873faf27403c74eab2399258c4d78`。

## 坐标换算与本机控制设计参考

- 项目：[ios151/wloc](https://github.com/ios151/wloc)，固定版本 `264641e856e5006cb1219777ec5f337d55d73a0c`，AGPL-3.0。
- `WLoc/Core/Coordinates.swift` 中 GCJ-02 正反算公式由该项目 `worker/src/gcj-browser.js` 移植为 Swift，保留其迭代逆算设计。
- 参考该项目通过 Surge HTTP request 脚本、本机 persistentStore 保存坐标的设计；本项目采用独立路径、独立存储键和配对鉴权，并提供原生界面。
- 新增 SwiftUI 界面、地图链接解析和本机控制脚本由 JavaWeh WLoc Native 项目维护，同样以 AGPL-3.0-or-later 提供。

源码与构建流程公开于 <https://github.com/JavaWeh/wloc-ios>。分发修改版或提供网络交互服务时，请保留许可证、作者信息、修改说明并依照许可证提供对应源码。
