> **RocketMQ 笔记核心编排准则清单**
>
> 1. **结构与格式极简**：拒绝长篇大论；所有知识点剥离进"核心职责"等平级标题下；**根据逻辑关联灵活结合有序列表（先后顺序）与无序列表（平级陈述）**；视觉对标 `Redis.md`。
> 2. **内容去水存精**：剥离通俗比喻，仅留存"专业架构视角"精炼总结；重点突出高并发、高可用、分片路由等体现分布式架构基石的关键设计。
> 3. **工作流步步为营**：大纲先行独立化；大段写入必须预先通过方案审核；全程聚焦全中文输出。

---

# 基础架构与核心组件
<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ.drawio.svg" alt="RocketMQ.drawio"/>

## NameServer

- **核心职责：路由管理与服务发现**
  1. **主动注册**：Broker 启动时向所有 NameServer 注册 Topic/Queue 路由信息。
  2. **定期拉取**：客户端（Producer/Consumer）后台定时从 NameServer 拉取路由并缓存至本地。
- **状态维护（心跳机制）**
  1. **上报**：Broker 每 `30s` 发送心跳包。
  2. **扫描**：NameServer 每 `10s` 扫描存活表。
  3. **剔除**：连续 `120s` 无心跳即判定失活并剔除。
- **架构设计特色**
  - **无状态零耦合**：节点间完全独立、互不通信，无主从、无复制依赖。
  - **AP 模型**：放弃强一致共识算法（Raft/ZAB），路由一致性为最终一致。
  - **客户端容错兜底**：依赖生产者重试与故障延迟机制屏蔽路由不精确。

## Broker

- **核心职责：消息存储与投递**
  - 负责消息的接收、持久化存储与消费投递。
  - 提供消息查询、高可用容灾、堆积预警等高级能力。
- **高可用能力 (Master-Slave)**
  - **Master**：独占承担客户端读写请求。
  - **Slave**：作为热备，持续同步 Master 的 CommitLog 数据。
  - **读降级**：Master 高载或宕机时，消费者自动引流至 Slave 读取。
- **架构设计特色**
  - **混合存储**：全量 Topic 消息顺序追加写入单一 CommitLog 文件，压榨顺序 IO 性能。
  - **零拷贝加速**：Mmap + PageCache 使文件读写性能逼近内存级。
  - **灵活数据安全组合**：提供"同步/异步刷盘"与"同步/异步复制"的自由组合。
  - **Shared-Nothing 横向扩展**：Master 间互不共享磁盘与索引，Topic 队列物理打散至多 Broker，消除锁竞争。

## Producer

- **核心职责：消息生成与发送**
  - 将业务数据封装为 Message 并投递至目标 Topic。
- **发送流程与容错**
  1. **获取路由**：首次发送向 NameServer 拉取 Topic 路由表，后台每 `30s` 定时刷新。
  2. **负载均衡**：默认轮询选择 MessageQueue，将消息分发到不同 Broker。
  3. **故障转移重试**：发送失败触发内置重试（默认 `2次`），强制切换至健康 Broker 节点。
- **发送模式**
  - **同步发送 (Sync)**：阻塞等待 Broker ACK，保障强一致（默认）。
  - **异步发送 (Async)**：不阻塞线程，回调处理结果，追求高吞吐。
  - **单向发送 (Oneway)**：发后即忘，适用于埋点日志等低可靠场景。

## Consumer

- **核心职责：消息获取与业务执行**
  - 从 Broker 拉取消息，交由本地线程池执行业务逻辑。
- **消费模式**
  - **集群消费 (Clustering / 默认)**：组内节点协同分担，一条消息仅被组内一台实例消费。
  - **广播消费 (Broadcasting)**：组内每台实例均收到完整副本，适用于全节点缓存刷新。
- **架构设计特色**
  - **长轮询 Pull**：不论 Push/Pull API，底层统一为长轮询 Pull 机制，兼顾实时性与反压。
  - **Rebalance**：组内实例上下线时自动触发 Queue 重新分配，接管孤儿队列消费权。
  - **Offset 管理**：集群模式下 Offset 由 Broker 端集中持久化，宕机恢复依赖已提交位点。

## 概念模型梳理

- **Topic 与 Tag**
  - **Topic**：一级业务消息通道（如 `OrderTopic`）。
  - **Tag**：Topic 内二级过滤标签（如 `TagA=创建`, `TagB=支付`）。
  - **服务端过滤**：Broker 基于 Tag 在服务端预过滤，减少无效网络传输。
- **MessageQueue**
  - **逻辑定位**：Topic 的物理分片（Partition）单元。
  - **存储本质**：不存放真实消息，仅存放指向 CommitLog 的索引条目（Offset、Size 等）。
  - **4.x 队列粒度互斥 (经典模型)**：集群模式下，同一 Queue 同一时刻仅被锁定分配给组内一台 Consumer 实例，形成扩容物理上限。
  - **5.x 消息粒度并发 (演进架构)**：打破队列独占铁律。基于单条消息内置 **不可见锁 (Invisible Lock)**，允许同组多实例同时无锁拉取同一 Queue，实现无极横向扩容。
  - *注：不同 Consumer Group 互不影响，各自独立享有全部 Queue 的消费权。*
- **Message**
  - **MsgId**：全局唯一消息标识，用于消息追踪。
  - **Keys**：业务自定义主键（如 `OrderID`），用于 IndexFile 追踪排查与补录。
  - **Body**：真实消息体，存于 CommitLog。

# 消息类型

## 普通消息

- **核心定位**
  - 最基础消息类型，无顺序、延迟、事务等附加语义。
  - 适用场景：日志采集、埋点监控、异步通知等吞吐优先场景。
- **端到端流转**
  1. **生产端**：Producer 轮询选择 MessageQueue 投递消息。
  2. **服务端**：Broker 顺序追加写入 CommitLog，异步构建 ConsumeQueue 与 IndexFile 索引。
  3. **消费端**：Consumer 依据 Offset 拉取 ConsumeQueue 索引，回查 CommitLog 获取消息体。
- **架构特征**
  - 无特殊语义约束，消息可全量打散至所有 Queue，收发性能最高。
  - 容错链路极简：发送失败直接重试，消费失败打回重放，无上下文依赖。

## 顺序消息

![RocketMQ-线程池乱序消费示意图.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-线程池乱序消费示意图.drawio.svg)

- **核心定位**
  - 保证消费端严格按照生产端发送顺序处理消息。
  - 适用场景：强状态机流转业务（如订单 `创建 -> 支付 -> 发货 -> 完成`）。
- **全局顺序 vs 局部顺序**
  - **全局顺序**：整个 Topic 单 Queue 单 Consumer，吞吐极低，极少使用。
  - **局部顺序（主流）**：仅保证同 ShardingKey（如同一 OrderID）消息有序，不同 Key 间并发处理。
- **局部顺序保障链路**
  1. **生产端**：提供 `ShardingKey`，Producer 按 Hash 值将同 Key 消息路由至同一 Queue。
  2. **存储端**：MessageQueue 天然 FIFO，同 Queue 内写入顺序即消费顺序。
  3. **消费端**：对顺序 Queue 加排他锁（`MessageQueueLock`），废弃线程池并发，强制单线程串行消费。
- **高阶调优**
  - 调大 `consumeMessageBatchMaxSize`，单线程批量拉取消息（如 10 条）。
  - 代码端转化为 Batch SQL 一次性写入 DB，兼顾顺序与聚合写入性能。

## 延迟/定时消息

![RocketMQ-延迟消息.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-延迟消息.drawio.svg)

- **核心定位**
  - 消息发送至 Broker 后不立即投递，延迟指定时间或到达绝对时间后才可消费。
  - 适用场景：订单超时关单、定时触达提醒，替代分布式定时任务扫描。
- **RocketMQ 4.x：固定级别延迟**
  - 仅内置 18 个固定延迟级别（1s, 5s ... 30m, 2h），不支持任意精度。
  - **暂存机制**：Broker 收到延迟消息后，暂存真实 Topic/QueueId，路由至内部 `SCHEDULE_TOPIC_XXXX` 对应级别队列。
  - **到期投递**：`ScheduleMessageService` 定时轮询延迟队列，到期后恢复原始 Topic 并重新写入正常队列。
- **RocketMQ 5.x：任意精度定时**
  - 引入 TimeWheel 算法引擎，支持毫秒级任意精度延迟/定时消息。
  - 保留"暂存 + 到期恢复"解耦模型，底层以刻度索引与滚动指针替代定时扫描。

## 事务消息

![RocketMQ-事务消息.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-事务消息.drawio.svg)

- **核心定位**
  - 保障本地事务与消息投递的最终一致性。
  - 适用场景：跨系统业务状态同步（如建单 + 库存预扣）。
  - 痛点：普通消息"先写库后发 MQ"或反之，均因缺乏原子性导致宕机时数据不一致。
- **两阶段提交流程**
  1. **预发送**：Producer 发送半消息至 Broker 隐藏队列 `RMQ_SYS_TRANS_HALF_TOPIC`，Consumer 不可见。
  2. **执行本地事务**：半消息发送成功后，Producer 执行本地 DB 写操作。
  3. **二次确认**：本地事务成功发送 `Commit`，半消息转入真实 Topic；失败发送 `Rollback`，Broker 丢弃半消息。
- **反查机制 (Check)**
  - **触发条件**：Producer 宕机或网络中断导致未发二次确认，Broker 扫描到超时半消息。
  - **回调寻址**：Broker 主动回调 `checkLocalTransaction` 接口查询本地事务状态。
  - **兜底闭环**：Producer 查询 DB 真实状态后补发 `Commit` 或 `Rollback`。

# 底层原理

## 存储机制

- **总体架构**：一个数据核心（CommitLog） + 两层独立索引（ConsumeQueue + IndexFile）。
- **CommitLog（数据主干）**
  - 存放所有 Topic 的真实消息内容，按接收时间顺序追加写入。
  - 全 Topic 混写单体文件，单段默认 1GB，充分利用顺序 IO 性能。
  - 结合 Mmap 机制提升高并发持久化吞吐。
- **ConsumeQueue（一级索引）**
  - 按 Topic/Queue 维度独立分文件，面向消费侧的路由映射索引。
  - 单条索引定长 20 字节：`CommitLog Offset` + `Message Size` + `Tag HashCode`。
  - 消费者先拉取轻量 CQ 锁定偏移量，再以 O(1) 定点回查 CommitLog 原始数据。
- **IndexFile（二级索引）**
  - 以消息 Key 为维度的哈希检索字典，专为生产环境异常溯源设计。
  - 底层基于 Hash 槽 + 拉链法解决哈希碰撞。
  - 索引节点存储 CommitLog 绝对 Offset，支持按业务单号秒级定位原始报文。

## 零拷贝与高效读写机制

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-mmap vs 传统io.drawio.svg" alt="RocketMQ-mmap vs 传统io.drawio"  />

- **Mmap（内存映射）**
  - **传统 IO 痛点**：读写涉及内核态与用户态间频繁数据拷贝与上下文切换。
  - **映射机理**：将磁盘文件地址映射至用户进程虚拟内存，读写直接穿透至底层磁盘，消除冗余拷贝。
  - **落地约束**：Mmap 对映射文件大小有 OS 限制，RocketMQ 固化 CommitLog 为 1GB、ConsumeQueue 为约 5.72MB。
- **PageCache（页缓存）**

  ![RocketMQ-page cache.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-page cache.drawio.svg)

  - **写路径**：消息追加至 PageCache 后即返回成功，OS 后台异步刷脏至物理磁盘（异步刷盘模式）。
  - **读路径**：CommitLog 顺序追加写入，OS Read-Ahead 预读机制将后续数据提前装载至 PageCache。
  - **缓存命中**：消费者顺序消费场景下，后续所需数据几乎 100% 命中内存页，免除物理磁盘寻道。
- **高阶调优（预热与锁隔离）**
  - **缺页中断风险**：Mmap 初始仅分配虚拟地址，首次写入触发 PageFault 导致延迟抖动。
  - **文件预热**：`warmMappedFile` 提前填充占位符强制触发 OS 缺页分配，`mlock` 锁定内存防止换出至 Swap。
  - **TransientStorePool**：启用堆外内存池作为写缓冲，隔离 Java GC 暂停对高频持久化的干扰。

## 刷盘与高可用策略

- **刷盘策略 (Flush Disk)**
  - **核心命题**：PageCache 数据何时落盘至物理磁盘扇区的时机抉择。
  - **异步刷盘 (ASYNC_FLUSH / 默认)**
    - 消息写入 PageCache 后立即响应 ACK。
    - 内核后台线程依据脏页率阈值（`vm.dirty_background_ratio`）或固定间隔（默认 `500ms`）批量 `fsync`。
    - 优势：单机极速吞吐基石。风险：断电时 PageCache 中未刷盘数据有微量丢失可能。
  - **同步刷盘 (SYNC_FLUSH)**
    - 消息写入 PageCache 后，强制唤醒 `GroupCommitService` 发起 `fsync`，磁盘层确认后才响应 ACK。
    - 优势：绝对物理数据不丢。代价：`fsync` 涉及内核中断与磁盘寻道，吞吐跌至数千 TPS 级。
- **主从备份策略 (Replication)**
  - **核心命题**：规避单节点存储介质不可逆损毁导致的数据湮灭。
  - **异步复制 (ASYNC_MASTER / 默认)**
    - Master 完成本地刷盘/写内存后即响应 ACK，后台 HA 线程异步向 Slave 推拉数据。
    - 优势：零阻塞，不拖累写入主线程。风险：Master 宕机时尾部未同步消息永久丢失。
  - **同步双写 (SYNC_MASTER)**
    - Master 接收消息并落盘后，阻塞业务线程。
    - `HAService` 流式推送至 Slave，Slave 写入 CommitLog 后回传 AckOffset。
    - Master 确认进度无误后唤醒业务线程，向外响应 SUCCESS。
    - 优势：金融级可靠，抵御单机房全毁。代价：附着网络 RT 开销，集群写吞吐小幅削减。
- **金融级最佳实践组合 (SYNC_MASTER + ASYNC_FLUSH)**
  - 主从同步双写 + 双机异步刷盘，放弃单机同步刷盘的吞吐损耗。
  - 跨机器/跨可用区 PageCache 级同步复制构建双倍冗余，单机断电时另一节点持有热数据并后台刷盘。

    ![RocketMQ-主从同步双写+双机异步刷盘.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-主从同步双写+双机异步刷盘.drawio.svg)

# 高级特性与面试常考场景

## 消息零丢失全链路方案

> [!IMPORTANT]
>
> **【重难点/架构】消息零丢失：端到端高可用与强一致性保障体系**

- **Producer 侧防丢**
  - 使用同步发送 (SYNC) 并校验 `SendResult`，严禁 Oneway。
  - 开启 `retryTimesWhenSendFailed` 多 Broker 转移重试。
  - 强一致业务源头采用事务消息（两阶段半消息 + 反查机制）。
- **Broker 存储侧防丢**
  - 配置 `SYNC_FLUSH` 强制同步刷盘，每条消息穿透 PageCache 直达物理磁盘。
  - 配置 `SYNC_MASTER` 同步双写，构建主从法定冗余副本。
- **Consumer 侧防丢**
  - 业务逻辑完整执行成功后方可提交 `CONSUME_SUCCESS`，严禁提前 ACK。
  - 消费失败由 Broker 重试队列（`%RETRY%Group`）阶梯延迟重推。
  - 重试耗尽（默认 `16` 次）后转入死信队列（`%DLQ%Group`），人工或脚本兜底恢复。
- **架构权衡 (Trade-off)**
  - 该方案偏向 CAP 中的 **CP** 模型，牺牲异步解耦带来的高可用性。
  - `SYNC_FLUSH + SYNC_MASTER` 叠加下，吞吐由十万级 TPS 骤降至数千级，RT 百倍级飙升。
  - 仅适用于金融级 P0 核心链路（支付结算、资金清算等），常规业务应回退异步集群模式。

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\RocketMQ-消息零丢失全链路.drawio.svg" alt="RocketMQ-消息零丢失全链路.drawio" style="zoom:80%;" />

## 消息消费幂等性保证方案

> [!IMPORTANT]
>
> **【重难点/架构】At Least Once 语义下的业务防重构型**

- **重复消费根因**
  - **ACK 丢失**：业务执行成功但 `CONSUME_SUCCESS` 回传时网络抖动，Broker 未记录进度导致二次投递。
  - **Rebalance 截断**：组内节点上下线触发重平衡，旧节点未提交的 Offset 被抛弃，新节点从旧位点重新拉取。
  - **语义底线**：RocketMQ 仅保障 `At Least Once`，不保障 `Exactly Once`，防重责任下推至业务系统。
- **方案一：去重表（数据库唯一键）**
  - 建立 `Message_Idempotent` 去重表，将 MessageID/业务单号设为 `Unique Key`。
  - 业务落库与去重写入包裹于同一事务上下文中。
  - 重放时 `INSERT` 触发 `DuplicateKeyException`，捕获后直接返回 `SUCCESS`。
- **方案二：状态机 + CAS 乐观锁**
  - 适用于强状态流转业务（如订单流转：待支付 → 已支付 → 已发货）。
  - 业务表引入 `Version` 字段或基于不可逆状态条件更新。
  - 执行 `UPDATE ... WHERE status = 'UNPAID'`，重放时 `affected_rows = 0` 即判定重复，静默跳过。

## 消息积压与消费堆积治理方案

> [!CAUTION]
>
> **【高危/架构】大规模消息堆积根因排查与分流预案**

- **积压根因定位**
  - **流入暴增**：大促或突发故障导致 Producer 发送速率反超 Consumer 处理水位。
  - **流出瓶颈**：下游 DB 慢查询/死锁、RPC 接口熔断导致单条消费 RT 指数级拉长。
  - **Rebalance 停滞**：Consumer OOM 或网络分区触发全组重平衡，Queue 消费进程短暂停滞。
- **预案一：Scale-Out 扩容**
  - 紧急扩充 Consumer 实例数量，同步增加 Topic Queue 分片数。
  - **物理约束**：同一 Queue 同时仅允许一个 Consumer 独占，实例数不得超过 Queue 数。
  - 若 16 个 Queue 扩容至 30 台 Consumer，多出 14 台完全空闲，无积压处理增益。
- **预案二：中转 Topic 导流**
  - 适用场景：原 Queue 分片触达扩容上限，业务耗时瓶颈短期无法拔除。
  - 执行步骤：
    1. **限流闭锁**：下线原 Consumer 集群的重度业务逻辑层。
    2. **降级转发**：节点降级为轻量分拣站，高速拉取并转发至临时大分片 Topic（Queue 数 10 倍以上）。
    3. **并行消费**：部署等量于新 Queue 数的 Consumer 集群挂载临时 Topic 并行清理积压。
- **预案三：调优与降级**
  - **批量聚合**：上调 `consumeMessageBatchMaxSize`，批处理聚合落库减少建连与 SQL 解析开销。
  - **全局降级**：弱依赖旁路场景（如日志打点）直接短路空转，`return SUCCESS` 签收丢弃滞后报文止血。

## DLedger 高可用集群与自动主从切换

> [!IMPORTANT]
>
> **【重难点/架构】基于 Raft 协议的去中心化故障自愈体系**

- **传统主从架构痛点**
  - RocketMQ 4.5 前，`BrokerId=0` 定义单点 Master，Slave 无法自动晋升。
  - Master 宕机后集群丧失该组写入能力，需运维人工修改配置并重启恢复。
- **DLedger 重构原理**
  - 抛弃 CommitLog 主从心跳复制，引入基于 **Raft 共识算法**的 `DLedger CommitLog` 组件。
  - 集群必须 `2n+1` 奇数节点部署，防止偶数分割导致脑裂 (Split-Brain)。
- **状态流转与选举**
  - **节点三态**：`Leader`（主）/ `Follower`（从）/ `Candidate`（候选人）。
  - **选举触发**：Leader 维系高频 Heartbeat；Follower 在随机偏移超时内未收到心跳，跃迁为 Candidate 发起 RequestVote。
  - **Majority 晋升**：获得超半数选票（如 3 节点中 2 票）即完成 Term 递增，接管 Leader 角色开放读写。
- **数据对齐与延迟消除**
  - **Uncommitted**：客户端写入直达 Leader，Leader 本地追加日志为 `Pending` 态。
  - **Majority 确认**：Leader 并发广播至 Follower，过半节点写入并 ACK 后标记 `Committed` 并释放响应。
  - **原生 SYNC_MASTER 缺陷**：强依赖唯一 Slave，该 Slave 抖动（网络/PageFault/GC）直接拖长 Master RT（木桶效应）。
  - **DLedger 破局**：1 主 2 从下，Leader 仅等最快的 Follower 即可凑足半数，彻底抹平单机卡顿长尾毛刺。

### Raft 强一致性共识算法剖析

> [!NOTE]
>
> **【底层原理】分布式系统的基石：强一致状态机复制与 CFT 容灾模型**

- **节点角色与逻辑时钟 (Term)**
  - **三态轮转**：全网节点锚定为 `Leader` / `Follower` / `Candidate` 之一。
  - **Term 单调递增**：作为全局逻辑防伪时钟，高版本 Term 无条件覆写低版本决策。
  - **防脑裂**：Term 机制从根本上阻断因网络分区导致双 Leader 多点写入的灾难性场景。
- **选举机制 (Leader Election)**
  - **心跳宣示**：Leader 高频多播 `AppendEntries`（空日志/心跳）维系主权。
  - **随机超时触发**：Follower 挂载独立随机偏移倒计时，超时清零即判定主节点失联，跃迁 Candidate 并全局 RequestVote。
  - **Majority 胜出**：率先获得 `(N/2)+1` 票的 Candidate 宣任为新 Leader。
- **日志复制 (Log Replication)**
  - **写入口收敛**：全网仅 Leader 接收外部写请求，Follower 收到后强制重定向至 Leader。
  - **两阶段同步**：
    1. **Uncommitted**：Leader 将写指令追加至本地日志，游标为 `Pending` 态，不对外可见。
    2. **并发复写**：Leader 并发调用 Follower RPC 复制同一份报文至各自本地磁盘 Log。
    3. **Committed**：超半数节点 ACK 后，Leader 将日志升阶为 `Committed` 态并向 Producer 回传成功。
- **架构澄清：HA vs Sharding**
  - **Raft 解决 HA**：一组 DLedger 纯粹用于高可用防丢与自愈，跨机器复制必然损耗单点吞吐。
  - **Sharding 解决并发**：横向铺设多组平行 DLedger Group，将 Queue 均匀打散至多组，实现 Scale-Out 无上限扩展。

### Controller 模式：控制面与数据面解耦

> [!NOTE]
>
> **【架构演进】从 Raft 嵌入存储层到独立控制面选主**

- **DLedger 模式的三大致命瓶颈**
  - **存储层入侵**：`DLedgerCommitLog` 整体替换原生 CommitLog，无法复用 `TransientStorePool`、`Zero-Copy` 等核心性能优化。
  - **副本成本刚性**：Raft 多数派强制要求 ≥ 3 节点，2 节点主从无法享受自动故障切换。
  - **双轨复制撕裂**：系统同时存在原生 HA 复制与 DLedger Raft 日志复制两套不兼容链路。
- **Controller 架构重构**
  - **核心思想**：将选主逻辑从 Broker 数据面剥离至独立的 **Controller 控制面**，Broker 回归原生 CommitLog 全栈存储。
  - **部署形态**：Controller 可独立部署或嵌入 NameServer。自身内部以 DLedger (Raft) 选出 **Active Controller**，≥ 3 节点保障容灾。
  - **Broker 角色动态化**：Broker 不再手动配置 `brokerRole` 与 `brokerId`，启动时向 Controller 注册，由 Controller 统一分配角色。
- **选主与故障切换机制**
  - **SyncStateSet（候选人池）**：Master 维护一组数据同步进度已追平的 Broker 集合，选主仅从该池中提拔，保障数据安全。
  - **秒级心跳探测**：Broker 以 **1s** 频率向 Controller 上报心跳（旧版 30s），超时 **5~10s** 即判定失效并触发选主（旧版 120s）。
  - **masterEpoch 防脑裂**：每次选主递增任期号，旧 Master 网络恢复后发现 Epoch 过期自动降级为 Slave。
  - **AutoSwitchHAService**：统一的主从日志复制与角色切换服务，HandShake 阶段自动完成日志截断对齐，替代双轨复制。

# Go 微服务生态生产级集成实战

## 1. 高可用发送端：多级降级与容错

- **策略要点**
  - 优先批量 `SendSync`，失败降级逐条发送，仅隔离毒消息，避免批次连坐。
  - 仅在 `SendOK` 后提交上游位点。

```go
// ========= 提炼自项目 Forwarder 的高级发送骨架 =========

var batchMsgs []*primitive.Message
pMsg := primitive.NewMessage("order_created", []byte(payloadStr))
pMsg.WithKeys([]string{orderID})        // 注入业务主键供下游幂等
pMsg.WithProperty("trace_id", traceID)  // 链路追踪透传
batchMsgs = append(batchMsgs, pMsg)

// 批量发送
res, err := f.producer.SendSync(ctx, batchMsgs...)

if err != nil {
    // 批量投递失败，降级退化为逐条排查发送 (Fallback)
    f.sequentialSend(ctx, batchMsgs)
    return
}

// 严苛状态仲裁
if res.Status == primitive.SendOK {
    commitOffset() // 仅在绝对 OK 时签收上游游标
} else {
    // 出现 FlushDiskTimeout 等集群临时抖动，退化为逐条重试
    f.sequentialSend(ctx, batchMsgs)
}
```

## 2. 强一致消费端：主动死信托管与防击穿幂等

- **策略要点**
  - DB 唯一索引冲突 (Error 1062) 实现终极兜底幂等，替代 Redis 查防。
  - `ReconsumeTimes >= 3` 时主动转发至专属 DLQ，阻断毒消息持续霸占线程。

```go
// ========= 提炼自项目 Consumer 的防弹消费骨架 =========

c, _ := rocketmq.NewPushConsumer(
    consumer.WithGroupName("group_order_consumer"),
    consumer.WithNameServer([]string{"127.0.0.1:9876"}),
    consumer.WithMaxReconsumeTimes(3),
    consumer.WithConsumerModel(consumer.Clustering),
    consumer.WithConsumeMessageBatchMaxSize(32),
)

c.Subscribe("order_created", consumer.MessageSelector{}, func(ctx context.Context, msgs ...*primitive.MessageExt) (consumer.ConsumeResult, error) {
    for _, msg := range msgs {
        err := f.repo.InsertOrder(ctx, parse(msg.Body))
        if err != nil {
            // 【主键冲突兜底幂等】
            var mysqlErr *mysql.MySQLError
            if errors.As(err, &mysqlErr) && mysqlErr.Number == 1062 {
                continue // 物理忽略重复消息，计为成功
            }

            // 【主动拦截并发往死信】
            if msg.ReconsumeTimes >= 3 {
                f.sendToDLQ(ctx, msg, err.Error())
                continue // 拦截毒药报错，释放阻塞
            }

            // 正常宕机，要求 MQ 阶梯重发
            return consumer.ConsumeRetryLater, nil
        }
    }
    return consumer.ConsumeSuccess, nil
})
```
