# 代码审计记录

## 2.1.0（构建 4）：五端配对与快捷安装

新增独立工具配对、固定提交的专属配置生成、随机令牌及随机端口的短时回环下载服务、文件分享备用路径，以及五款工具的本机控制和二进制适配。旧版 Surge 配对和收藏保留。

鉴权边界由专属配置中精确的密钥路径匹配及脚本内请求头校验共同构成；通配密钥路径不安全，禁止改成通配规则。健康检查不含密钥或坐标，客户端身份不匹配时停止认证请求。App 不记录专属 URL；代理工具自身的日志可能含 URL，用户不得分享原始认证路径。

临时服务仅监听 127.0.0.1，最多 120 秒，iOS 后台到期时主动关闭；仅 GET/HEAD 指定文件，限制请求头、并发连接、单连接时间和下载次数。运行时脚本不引用临时地址，也不请求远程坐标配置。QX 单独区分 header-only echo 读取与 body-analyze echo 写入。

验证完成：[2.1.0 macOS 构建](https://github.com/JavaWeh/wloc-ios/actions/runs/39232732356) 成功，代码提交 `9eae529672ab574e807ad2fe453dff13c23719c5`。40 项 Swift 测试零失败（原有 27 项、新增 13 项），包含实际回环监听、停止及定时过期测试；五端 Node 协议与真实 WLOC 二进制集成、Swift 实际生成的匹配规则、旧 Surge 集成和 3 项 Python 打包测试通过，生成脚本可复现，iPhoneOS Release 编译完成。临时服务使用串行队列隔离状态，已明确其 Sendable 边界；最终构建无源代码并发警告，仅有未使用 AppIntents 时 Xcode 跳过元数据提取的提示。

[下载该次 IPA](https://github.com/JavaWeh/wloc-ios/actions/runs/39232732356/artifacts/12178241922)（需登录 GitHub，保留 14 天）。下载后复核：版本 2.1.0、构建 4、Bundle ID `com.wloc.quicklocation`、iPhoneOS arm64 Mach-O、可执行权限、随包许可证及未签名状态均符合预期；IPA 中固定脚本提交号与上述构建提交一致。IPA 为 397000 字节，SHA-256：`46683177923029ce39778ce5e5c110e7e39453c08db54cb36d7564cf63f8fb29`。

所有五款工具的快捷导入、文件导入、重启后保留、关闭 WLoc 后继续运行及系统定位效果，均待真机验证。QX 和 Shadowrocket 默认优先文件导入，其他工具快捷下载也标记实验性；不得将“URL 已打开”或协议模拟通过标成真机完成。

## 2.0.1（构建 3）历史审计

日期：2026-10-19。基线：`f282de43963cef224efa2ec2b31aeeb146a97803`。

范围：原生地图与分享链接导入、坐标转换调用、收藏持久化、Surge 本机控制鉴权及 WLOC 配置边界、工程生成和 IPA 打包。上游 protobuf 实现仅检查本项目的接入、配置验证和二进制集成行为；本次不构成对全部上游依赖或 iOS 系统的安全认证。

## 已修复的问题

| 级别 | 问题及影响 | 修复 |
| --- | --- | --- |
| P1 | 原生 MapKit 坐标被当作网页 GCJ-02 再次转换，可能导致导入和预览偏移 | `ImportPlaceView.swift` 按原生接口 WGS-84 契约传入、保存和预览；分享链接保留明确的坐标系确认 |
| P1 | Google 查询文字和片段中的 `@`、`!3d/!4d` 可能被误读成坐标；有地点 ID 时可能误用回退坐标 | `MapLinkParser.swift` 限定路径、data 参数来源；拒绝无法还原的地点 ID，不猜测地点 |
| P2 | 修改输入、解析失败或异步结果返回较晚时，旧地点坐标或名称仍可能被收藏 | 新增 `MapImportDraft` 状态版本；输入变化清空草稿、取消请求；仅接受当前版本结果；搜索结果检查当前查询 |
| P2 | 响应大小限制发生在完整下载之后，无法限制大响应的资源消耗 | 新增 `BoundedHTTP` 流式读取，检查声明长度及实际字节数，超限、错误或结束时取消任务；短链上限 512 KiB，控制响应上限 64 KiB |
| P2 | 收藏损坏后直接使用空列表继续保存，可能覆盖仅存的原始数据 | 新增 `FavoritesStore`，先验证全部记录及唯一 ID；损坏内容先复制到 UUID 恢复文件；无法读取或备份时禁止写入；钥匙串读取独立执行 |
| P2 | 仅校验精度为正数，极大数值可能无法被 WLOC 整数编码表示 | Swift、Surge 控制脚本和生成的响应脚本统一限制精度 1～1,000,000 米；无效持久化配置直接透传原响应 |

原生坐标处理依据：[Apple CLLocationCoordinate2D 文档](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d) 的 WGS-84 约定。Google 地点 ID 优先于回退查询的行为依据：[Google Maps URLs 官方说明](https://developers.google.com/maps/documentation/urls/get-started)。流式任务取消接口依据：[Apple URLSession.AsyncBytes.task](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes/task)。

## 验证

- 新增 10 项 Swift 回归测试，覆盖错误坐标来源、地点 ID、过期草稿、收藏恢复及写保护、精度边界，以及服务端不结束响应时主动取消超限传输。
- Windows 本地：Surge 控制与真实二进制 WLOC 集成测试通过；3 项 Python 打包测试通过；16 份 Swift 文件语法检查及 Xcode 工程结构检查通过。
- [macOS GitHub Actions 构建](https://github.com/JavaWeh/wloc-ios/actions/runs/39228561774) 已成功，构建代码提交为 `659b25c6540055f99ef5a1674d2b21b2f015c9d1`：27 项 Swift 测试零失败，Surge 集成与 3 项 Python 测试通过，iPhoneOS Release 编译和 IPA 打包完成。
- 下载产物后再次核验：版本 2.0.1、构建 3、arm64 设备 Mach-O、可执行权限、随包许可证及未签名状态均符合预期；IPA 为 310315 字节，SHA-256 为 `c8167159299f3d2c271481a128e25796823ec89c4401ade2e18d8632bc67be05`。
- [下载该次 IPA 产物](https://github.com/JavaWeh/wloc-ios/actions/runs/39228561774/artifacts/12176021408)（需登录 GitHub，产物保留 14 天，过期后重新构建）。

## 尚需真机确认

用户此前确认上游网页方式在 iOS 26.4 可生效；这不等同于本 App 已通过真机验证。本次未实际运行 iPhone，需安装后确认 Surge 配对、原生 MapKit 与分享链接坐标、开启与关闭后的系统定位行为。

地图分享链接中的坐标系仍有来源差异，区域默认判断只能辅助确认；地点 ID、反爬或依赖脚本的短链可能无法解析。iOS 定位缓存及 GPS 优先级不受 App 控制。未签名 IPA 必须使用用户自己的签名安装。
