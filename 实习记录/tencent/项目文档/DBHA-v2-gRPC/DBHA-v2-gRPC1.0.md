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
   - 注：此处 context 计划在新增 case 中创建后再传入函数，与 `NewGSEClient()` 内部自己管理 context 保持一致
- `ReporterConfig` 新增 `clientID` 字段
- `Configuration` 顶层新增 `bkCloudID` 字段

## 模块 2：`ProbeServer` 接入 `Inputter` 接口

**改动文件**：`internal/receiver/source/probe/probe.go`、`internal/receiver/source/source.go`

- `NewProbeServer(cfg)` — 移除 savers 参数，只传入 cfg 以匹配 `NewInputter(cfg)`，等到 `inputter.Harvest` 传入 sinkers 时再给 savers 赋值 
- `Harvest(ctx, savers)` — 将 savers 存入 `p.savers`，goroutine 里调 `p.Run(ctx)`，立即返回 `nil`
- `Close()` — 已有实现，不变
- `NewInputter()` 新增 `case "probe"`，调用 `NewProbeServer(cfg)`

# 2. 风险与落地

## 2.1 预期调用路径

### server 启动
```
cmd/receiver/main.go
main()
   -> rootCmd.Execute()
      -> receiver.Run()
         -> svr.Run(ctx)
            -> CreateDiscovery()
            -> CreateSinkers()
            -> CreateSource(ctx)
               -> source.NewInputter(sourceCfg)
                  -> case "probe": // 新增
                        NewProbeServer(cfg) // 构造 ProbeServer - 改动函数签名
               -> inputter.Harvest(ctx, s.sinkers) // 新增
                  -> p.savers = sinkers // 注入 MySQLSinker
                  -> go p.Run(ctx) // goroutine 里启动 gRPC Server
                     -> grpc.NewServer()
                     -> proto.RegisterReceiverServiceServer(svr, p)
                     -> net.Listen("tcp", endpoint)
                     -> p.svr.Serve(listen) // 开始监听，等待客户端连接
            -> CreateApmServer()
```
结束状态：gRPC Server 已监听端口，p.savers 已注入 MySQLSinker，等待 probe 连接进来。

### Client 启动
```
cmd/probe/main.go
main()
   -> rootCmd.Execute()
      -> probe.Run()
         -> p.Run(ctx)
            -> loadPlugins(ctx)
               -> harvester.NewPluginMySql
               -> go runPlugin(ctx, plug) // 此处创建 eventC channel，等待数据
            -> createReporter()
               -> client.NewReporter(cfg)
                  -> case: "receiver": // 新增
                     -> NewReceiverClient(ctx, cfg.Endpoint, cfg.ClientID)
                        -> grpc.NewClient(endpoint) // 建立连接对象
            -> p.reporter = r
```
结束状态：ReceiverClient 已创建，gRPC 连接对象就绪（lazy connect，实际连接在首次 Send 时建立），runPlugin goroutine 已启动等待数据。

### 采集循环
本环节无改动。
```
Plugin.Harvest() // 以 MySQL 为例
   -> beginCollecting(wg, dataC)
      -> m.collecting() // 每个 Collector 并发执行
         -> obtainHostStatus() // 采集主机指标
         -> open() // 连接 DB，失败生成 DbEvent
         -> obtainGlobalStatus() // 采集 DB 状态
         -> dataC <- data // 写入 channel
```
结束状态：HarvestData 已写入 dataC，等待 runPlugin() 消费。

### Client 上报
```
runPlugin(ctx, plug)
   -> case data := <- eventC: // 取出数据
      -> p.reporter.GetBaseInfo() // 新增
         -> return AgentID: r.clientId，BkCloudID: config.Cfg.BkCloudID
      -> json.Marshal(data)
      -> p.reporter.Post(ctx, dataEncoded) // 新增
         -> ReceiverClient.SendMessage(content)
            -> stream == nil
               -> createStream()
                  -> client.PushData(ctx) // 打开 stream
                  -> go monitorConnection() // 开始监控连接
            -> stream.Send(msg) // 发出数据
```
结束状态：HarvestData 的 JSON 字节已通过 gRPC 流帧发送出去，probe 端任务完成。

### Server 接收
本环节无改动。
```
PushData(stream)
   -> &connHandler{savers: p.savers} // 创建连接处理器并注入 MySQLSinker
   -> connHandler.run()
      -> go c.readEvent() // 消费数据
   -> default:
      -> stream.Recv()
      -> connHandler.postEvent(req) // 推送数据到 channel
         -> eventC <- event
```

### Server 持久化
本环节无改动。
```
c.readEvent()
   -> case msg := <-c.eventC:
      -> copy(data, msg)
      -> saver.Save(data)
         -> json.Unmarshal(data, dbStatus)
         -> hamodel.NewDbhaData(dbStatus)
         -> db.Clauses(OnConflict{UpdateAll: true}).Create()
```
结束状态：HarvestData 已持久化到 MySQL t_dbha_status 表，整条链路完成。

## 2.2 待确认问题

**GSE 通道静默失效时的通道切换**

GSE 通道断连后无自愈机制，`Post()` 失败仅记录 Warn 日志丢弃数据。当前设计中 probe 同一时刻只使用一个 Reporter，GSE 失效后不会自动切换到 gRPC 通道。待确认**是否需要支持通道降级/自动切换机制**（如 GSE 连续失败 N 次后自动切换到 gRPC Reporter）。