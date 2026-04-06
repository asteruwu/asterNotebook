# 角色

你是一位拥有多年经验的高级后端架构师。以下是你精通的技术栈：

- Go语言；
- Redis/MySQL/RocketMQ；
- Prometheus/Grafana/Jaeger；
- Docker/Kubernetes。

你有这样的资历与能力：

- 多次面对并解决过P0级事故；
- 精通高并发场景下**保障高性能与数据一致性**的系统设计；
- 擅长找出代码与系统设计中可能引起竞态条件或数据不一致的漏洞；擅长推导、还原复杂的状态机流转。

# 上下文

我正在基于Go语言重构一个微服务，改造核心是checkout服务下的placeorder环节，改造目标是：

**面对电商网站日常的突发高流量，系统在具备高性能(Redis做缓存)的同时，保障最终数据一致性(MySQL & Redis)。**

且：

**具备优秀的容灾能力：**在任何时刻，系统中的任意组件宕机时，数据均不会丢失(最终一致性)。

---

## 项目结构概览

```
src/
├── productcatalogservice/          # 商品目录服务
│   ├── server.go                   # 主入口，gRPC Server
│   ├── repository/
│   │   └── cached_repo.go          # Redis缓存层 + Lua脚本
│   ├── forwarder/
│   │   └── worker.go               # Redis→RocketMQ 转发器
│   └── worker/
│       ├── stream.go               # Stock Stream Worker
│       └── recover.go              # Stock Stream Recovery
│
└── orderservice/                   # 订单服务
    ├── main.go                     # 主入口，Worker 启动
    ├── pkg/service/
    │   └── service.go              # gRPC 业务逻辑
    ├── pkg/repository/
    │   └── order_repo.go           # MySQL 数据层
    └── pkg/worker/
        ├── consumer.go             # RocketMQ Consumer（订单创建 + 状态更新 + 发货）
        ├── cleanup.go              # 超时订单清理
        └── shipping_recover.go     # 发货补偿
```

---

## 正常下单流程

1. **[Frontend] PlaceOrder Request**

   前端向Checkout Service发起下单请求。

2. **[CheckoutService] Prepare OrderItems And ShippingQuote From Cart**

   内部函数调用，从用户购物车中获得所有商品，整理成生成订单所需的对象。

3. **[CheckoutService] Call Order Service**

   发起Create Order的请求，调用Order Service。

   1. **[OrderService] Create OrderID**
      > 📍 `orderservice/pkg/service/service.go` → `CreateOrder()` L46-48

      内部函数调用，生成具有唯一性的订单ID。

   2. **[OrderService] ChargeProduct Request**
      > 📍 `orderservice/pkg/service/service.go` → `CreateOrder()` L56-74

      向ProductCatalog Service发起扣减库存请求。

      1. **[ProductCatalogService] Data Construction**
         > 📍 `productcatalogservice/repository/cached_repo.go` → `ChargeProduct()` L313-370

         准备数据：

         - Keys
           - dedupKey（幂等键）: `"dedup:charge:{OrderID}"`
           - stockKey: `"product:stock:{ProductID}"`
           - streamKey: `"mq:stock:sync"`, `"mq:order:create"`

         - Values
           - 商品数量、stock/order JSON payload

      2. **[ProductCatalogService] Atomic Execution**
         > 📍 `productcatalogservice/repository/cached_repo.go` → `LuaDeductStock` L59-107

         执行Lua脚本（带幂等性检查）：

         1. **幂等性检查：** 检查 `dedupKey` 是否存在
            - 存在：返回 code=2（已处理过）
            - 不存在：执行下一步
         2. 检查库存是否足够
         3. 扣减库存
         4. 写入去重记录（TTL 1小时）
         5. 写入 stock/order Redis Stream

   3. **[OrderService] Charge Request**
      > 📍 `orderservice/pkg/service/service.go` → `CreateOrder()` L76-94

      1. 向Payment Service发起扣款请求
      2. 发送 `PAID` 状态消息到RocketMQ的`order_status_events`队列

   4. **[OrderService] Return Success**
      > 📍 `orderservice/pkg/service/service.go` → `CreateOrder()` L96-101

      返回成功响应。**发货由 MQ Consumer 驱动。**

4. **[CheckoutService] Empty User Cart & Send Confirmation**

---

## 异步 Worker 与 Recovery 机制

### Redis Stream Workers (ProductCatalogService)

#### stock stream worker
> 📍 `productcatalogservice/worker/stream.go` → `StockStreamWorker`

1. 定时从 `mq:stock:sync` 批量拉取消息
2. 在内存中聚合
3. MySQL 事务批量刷盘：幂等检查 → 扣减库存 → 记录MessageID
4. 向 stream 发送 ACK

#### stock stream recovery
> 📍 `productcatalogservice/worker/recover.go` → `StockRecoveryWorker`

1. 定时从 pending list 拉取并夺取处理权
2. 批量处理到 MySQL（同上）
3. 向 stream 发送 ACK

#### order stream forwarder
> 📍 `productcatalogservice/forwarder/worker.go` → `OrderForwarder`

**【架构改进】** 原设计中 OrderService 直连 Product Redis，现改为由 ProductCatalogService 内部的 Forwarder 转发，实现服务间物理解耦。

1. 从本地 Redis Stream `mq:order:create` 批量拉取（L84-90）
2. 使用熔断器保护，批量发送到 RocketMQ `order_created`（L193-195）
3. 批量失败时降级为逐条发送
4. 向 stream 发送 ACK

---

### RocketMQ Consumers (OrderService)

#### `order_created` consumer
> 📍 `orderservice/pkg/worker/consumer.go` → `handleOrderCreate()` L254-330

1. 定量读取批量消息
2. 在内存中聚合 → `InsertOrdersBatch()`
3. 失败降级：逐条 `InsertOrder()`
4. 返回 `ConsumeSuccess`

#### `order_status_events` consumer
> 📍 `orderservice/pkg/worker/consumer.go` → `handleOrderStatusUpdate()` L92-238

1. 定量读取批量消息
2. 批量更新订单状态 → `UpdateOrderStatusBatch()`
3. **对 PAID 订单触发发货：**
   - 批量获取订单 → `GetOrdersByIDs()` (L146-154)
   - 并发调用 `ShipOrder` RPC (L176-192)，限流10并发
   - 批量更新发货状态 → `UpdateOrdersAndInsertShipmentsBatch()` (L195-208)
   - RPC 失败返回 `ConsumeRetryLater`，由 MQ 自动重试
4. 返回 `ConsumeSuccess`

#### `DLQ` consumer
> 📍 `orderservice/pkg/worker/consumer.go` → DLQ 处理逻辑

1. 读取死信消息
2. 逐条插入到 MySQL 死信日志表

---

### Cleanup & Recovery Workers (OrderService)

#### cleanup worker
> 📍 `orderservice/pkg/worker/cleanup.go` → `OrderCleanupWorker`

专门用于处理 orders 表中超时（5分钟）且处于 Pending 状态的订单。

1. 定时扫描 MySQL → `GetExpiredPendingOrders()` (L59)
2. 并发查询 PaymentService 确认支付状态 (L86)
3. **分组处理：**
   - 已付款：批量更新状态为 PAID
   - 未付款：调用 `RestockProduct` 回滚库存 → 批量更新状态为 CANCELLED

#### shipping recover
> 📍 `orderservice/pkg/worker/shipping_recover.go` → `ShippingRecoverWorker`

专门用于处理已付款但尚未发货的订单（补偿机制）。

1. 定时扫描 MySQL → `GetPaidOrders()` 获取 PAID 状态超过1分钟的订单 (L54)
2. 调用 ShippingService 确认发货状态 (L115)
3. 未发货：重新尝试发货 → 批量更新状态 (L138-146)
4. 已发货：直接修复本地状态

---

## 架构改进总结 (v2.0)

| # | 改进点 | 原设计 | 改进后 | 关键代码 |
|---|--------|--------|--------|----------|
| 1 | **库存扣减幂等性** | Lua 无 OrderID 去重 | Lua 脚本增加 `dedupKey` 检查 | `cached_repo.go` L59-107 |
| 2 | **服务间 Redis 解耦** | OrderService 直连 Product Redis | ProductCatalog 内置 Forwarder | `forwarder/worker.go` |
| 3 | **发货可靠性** | `go func()` 内存异步发货 | MQ Consumer 驱动 + Recovery 补偿 | `consumer.go` L176-208 |

---

# 任务

完整阅读我的这套系统的所有代码，确认你了解所有的设计细节，包括同步的流程和异步的worke+补偿机制，复杂的数据流转，各个流程的调用链路，以及一些细节上对于性能的优化处理（比如批量处理数据 + 批量失败时的降级措施）。接下来我需要开始基于这个项目写一份简历，你需要确保你对这个项目充分了解。

# 约束

未经我的允许不要直接改动我的代码。
