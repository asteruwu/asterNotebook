项目根目录：./blueking-dbm/dbm-services/common/dbha-v2

# 1. 接口定义

1.1 RPC 方法

1.2 消息体结构

# 2. 接入主流程

2.1 probe 端：将 ReceiverClient 作为 Reporter 接入采集上报链路

2.2 receiver 端：将 ProbeServer 注册到 source 工厂，接入 Service 启动流程

# 3. 连接管理
3.1 client：长连接维护与重连策略

   - 已实现：
      
      - keepalive 保活（client: Time=5s/Timeout=10s，server: Time=5min/Timeout=10s）
      - monitorConnection() 每 5s 检测连接状态，断连后指数退避重连（基础间隔 5s，最大 10 次）

   - 待考虑：

      - **连接失败时区分错误码**：
         - codes.ResourceExhausted（连接数超限）→ 不重试当前地址，直接切换到下一个 receiver地址（依赖 6.2/6.3）；**无备用地址时告警并停止尝试**
         - 其他错误 → 走现有指数退避重连逻辑
      - **连接失败处理措施分级**：

         - 重连失败（未超上限）
            - 静默，继续退避重试

         - 重连放弃（超上限）
            - 有备用地址 → 切换地址，不告警
            - 无备用地址 → 告警（gRPC 通道彻底失效）

         - 连接数超限
            - 有备用地址 → 切换地址，不告警  
            - 无备用地址 → 告警（gRPC 通道彻底失效）

3.2 server：连接数上限与超限处理

   - 已实现：无

   - 待考虑：
      - Probe 结构体维护原子计数器感知当前连接数，最大值从配置读取
      - PushData 入口判断：超限返回 gRPC status codes.ResourceExhausted，直接拒绝
      - client 侧通过错误码区分「连接数超限」与其他网络错误，决定后续行为
      - 当前连接数纳入 5.1 的 Prometheus 指标（全局统计）

3.3 server：eventC 缓冲队列容量配置化

# 4. 错误处理
4.1 client：发送失败处理

   - 失败计数 +1，记录失败时间戳
   - 清理窗口期外的旧记录（滑动窗口，如 30s）
   - 窗口内失败次数 < 阈值（如 5 次）→ 丢弃，继续
   - 窗口内失败次数 ≥ 阈值 → 主动触发 stream 重建
      - 重建成功 → 清空计数，继续
      - 重建失败 → 交给现有 handleDisconnect() 走指数退避重连

4.2 client：放弃重连后的告警

4.3 server：队列满时的丢弃与记录

# 5. 可观测性
   5.1 server 端 Prometheus 指标（连接数、消息数、字节数、丢弃数、错误数）

   5.2 指标分组粒度（全局 vs 按 client_id label）

# 6. 需要确认

## 6.1 MySQL Sink 单条写入瓶颈

`connectionHandler` 逐条从 `eventC` 取出消息，每条对应一次 `INSERT ... ON CONFLICT UPDATE ALL`
SQL 往返。MySQL 的写入 QPS 直接决定了 gRPC 通道的吞吐上限。probe 数量多或探测间隔短时，
`eventC`（容量 1024）容易被打满，触发丢弃。

改为批量 Upsert 可显著提升吞吐，但属于 Sink 层优化，超出本次设计范围。

## 6.2 receiver 多实例容灾能力缺失

当前 probe 的 receiver 地址只能来自本地 YAML 配置，单点故障后无法自动切换到其他 receiver 实例。

根本原因是整条链路均未打通：
- receiver 启动时未将 gRPC 监听端口写入 etcd（`ServiceInfo.ProbeEndpoint` 为 nil）
- admin `GetProbeConfig` 未从 etcd 查询在线 receiver 列表并下发给 probe
- probe `ReceiverClient` 不支持多地址，无法在断连后轮换

完整解决需上述三步全部实现，超出本次设计范围。

对比 GSE 通道：probe 只连本机 socket，路由由蓝鲸管控平台基础设施托管，天然无单点问题。
gRPC 直连通道适合内网直连场景，多实例容灾需额外建设。

## 6.3 多 receiver 实例的负载均衡

gRPC 是长连接，负载均衡只发生在连接建立时，不会中途切换实例。

建议策略：连接建立时从地址列表中随机选取一个；断连重连时轮换到不同地址。
无需引入外部负载均衡组件，probe 侧自行实现即可。

依赖 6.2 的地址下发能力，6.2 未实现则本节无意义。

---

> 单 receiver 实例预演

已知现在有etcd，且receiver为多实例。但先考虑单实例情况下的处理策略。后续再考虑引入地址管理。在此背景下，receiver 地址固定来自本地配置，不涉及多地址管理。6.2/6.3 暂不实现。

### client 连接管理

- keepalive 保活 + 指数退避重连（已有，保留）
- 发送失败：滑动窗口计数（窗口 30s，阈值 5 次），超阈值主动重建 stream；
  重建失败交给 handleDisconnect() 走退避重连
- 连接失败统一处理：
  - codes.ResourceExhausted → 告警 + 停止重连，等待人工介入
  - 其他错误 → 指数退避重连
  - 放弃重连（超上限）→ 告警（gRPC 通道彻底失效）

### server 连接管理

- 原子计数器维护当前连接数，上限从配置读取
- PushData 入口超限 → 返回 codes.ResourceExhausted，直接拒绝
- eventC 缓冲队列容量从配置读取（默认 1024）
- 队列满 → 丢弃并计入指标；持续满时主动断连，让 probe 退避

### 可观测性

- 连接数：全局统计（Gauge）
- 接收消息数、字节数、错误数、丢弃数：按 client_id label 分组（Counter）
