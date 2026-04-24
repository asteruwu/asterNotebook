# DBHA-v2 gRPC 直连通道功能扩展设计文档

项目根目录：./blueking-dbm/dbm-services/common/dbha-v2

# 0. 需求与目标

## 0.1 核心问题

`dbha-v2` 现有的 probe → receiver 数据上报链路强依赖蓝鲸 GSE 管控平台（probe 通过 GSE Agent 将探测数据写入 Kafka，receiver 再从 Kafka 消费）。这条链路存在两个固有缺陷：

1. **平台强依赖**：在没有部署 GSE Agent 的环境中，probe 无法上报数据，整个 HA 检测能力失效。
2. **运行时静默失效**：GSE 通道断连后无自愈机制，`Post()` 失败仅记录 Warn 日志并丢弃数据，系统无感知。

本次扩展的目标是**打通已有但未接入的 gRPC 直连通道**（proto/IDL、客户端、服务端代码均已存在），使 probe 可以绕过 GSE，直接通过 gRPC 流式连接将探测数据推送给 receiver，作为 GSE 通道的**替代或补充**，增强上报链路的适应性与可靠性。

## 0.2 核心功能边界

1. **probe 端：接入 gRPC Reporter**
   - 将 `ReceiverClient` 包装为 `Reporter` 接口实现
   - 在 `NewReporter()` 工厂注册 `case "receiver"`
   - `GetBaseInfo()` 中 `BkCloudID` 从配置读取，`AgentID` 复用 `clientID`

2. **receiver 端：接入 gRPC Source**
   - 将 `ProbeServer` 接入 `Inputter` 接口
   - 在 `NewInputter()` 工厂注册 `case "probe"`

3. **配置扩展**
   - probe 的 `Configuration` 顶层新增 `bkCloudID` 字段（机器云区域归属，与 `serviceID` 同级）
   - probe 的 `ReporterConfig` 新增 `clientID` 字段（gRPC 连接身份标识，与 `dataID` 同级，各 Reporter 按需使用）
   - 两端均通过 `name` 字段按需切换通道，向后兼容

# 1. 具体逻辑规划

## 模块 1：`ReceiverClient` 包装为 `Reporter` 接口

**改动文件**：`internal/probe/client/receiver.go`、`internal/probe/client/reporter.go`、`internal/probe/config/config.go`

- `Name()` — 返回常量 `"receiver"`
- `Post(ctx, content)` — 调用 `SendMessage(content)`
- `GetBaseInfo()` — 返回 `AgentID: r.clientId`，`BkCloudID: config.Cfg.BkCloudID`
- `Close()` — 调用已有 `ReceiverClient.Close()`
- `NewReporter()` 新增 `case "receiver"`，调用 `NewReceiverClient(ctx, cfg.Endpoint, cfg.ClientID)`
- `ReporterConfig` 新增 `clientID` 字段
- `Configuration` 顶层新增 `bkCloudID` 字段

## 模块 2：`ProbeServer` 接入 `Inputter` 接口

**改动文件**：`internal/receiver/source/probe/probe.go`、`internal/receiver/source/source.go`

- `NewProbeServer(cfg, savers)` — 移除 savers 参数，只传入 cfg 以匹配 `NewInputter(cfg)`，等到 `inputter.Harvest` 传入 sinkers 时再给 savers 赋值 
- `Harvest(ctx, savers)` — 将 savers 存入 `p.savers`，goroutine 里调 `p.Run(ctx)`，立即返回 `nil`
- `Close()` — 已有实现，不变
- `NewInputter()` 新增 `case "probe"`，调用 `NewProbeServer(cfg)`

# 2. 风险与落地

## 2.1 待确认问题

**GSE 通道静默失效时的通道切换**

GSE 通道断连后无自愈机制，`Post()` 失败仅记录 Warn 日志丢弃数据。当前设计中 probe 同一时刻只使用一个 Reporter，GSE 失效后不会自动切换到 gRPC 通道。待确认**是否需要支持通道降级/自动切换机制**（如 GSE 连续失败 N 次后自动切换到 gRPC Reporter）。
