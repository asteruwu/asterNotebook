## 1. 架构设计概览

本项目旨在构建一个能够支撑高并发流量（10k+ QPS）的商品库存服务，核心设计目标是在保证高性能响应的同时，实现数据的最终一致性。

**1.1 技术栈**

- **计算层：** Go (gRPC / Microservices), Kubernetes / Docker
- **存储层：** Redis (Sentinel Mode, AOF Enabled), MySQL (InnoDB)
- **可观测性：** Jaeger (Tracing), Prometheus (Metrics)

**1.2 核心模式：异步削峰与写回** 针对热点商品的库存扣减，摒弃了直接操作 MySQL 的传统方案，采用 **Redis + Lua + Stream** 的异步架构：

1. **原子扣减 :**
   - 利用 Redis Lua 脚本实现 `Check-and-Set` 逻辑。
   - 脚本原子性地执行：检查 Redis 库存 -> `DECRBY` 扣减 -> `XADD` 写入 Redis Stream 消息队列。
   - **优势：** 消除数据库行锁竞争，将热点写操作完全内存化。
2. **异步落库:**
   - Go 服务内部启动 `Goroutine Worker` 消费 Redis Stream。
   - 采用 **Buffer Batch** 机制：在内存中聚合多条扣减请求，批量更新 MySQL (`UPDATE product SET stock = stock - ?`)。
   - **可靠性保障：**
     - **幂等性 :** 引入 `stock_dedup_log` 表，利用 Stream Message ID 防止消息重复消费。
     - **故障恢复:** 实现了 Pending List 监控，通过 `XCLAIM` 机制主动捞取并重放消费者崩溃后未 ACK 的死信消息。
3. **读路径优化:**
   - 采用 **Cache-Aside** 模式，配合 `Singleflight` 防止缓存击穿。
   - 引入 `Gobreaker` 熔断器保护下游数据库。





## 2. 问题描述

在对该架构进行最终压力测试（Tool: `ghz`）时，发现在不同基础设施环境下，系统表现出极大的**数据一致性差异**。

**2.1 环境对比**

| **维度**       | **环境 A：本地开发环境 (WSL2 + Minikube)** | **环境 B：生产模拟环境 (CNB + Docker)** |
| -------------- | ------------------------------------------ | --------------------------------------- |
| **基础设施**   | Windows 虚拟化层，I/O 性能受限             | Linux 原生容器环境，高性能 SSD          |
| **压测表现**   | P99 延迟较高 (100ms)，吞吐量受限           | **P99 < 20ms**，吞吐量极高              |
| **数据一致性** | **完全一致** (Redis 最终值 == MySQL 值)    | **严重不一致 (存在库存丢失/超卖)**      |

**2.2 故障现象** 在环境 B（高性能环境）中：

1. **库存超卖：** 压测显示 Redis 中库存已正确扣减，但 MySQL 中该商品库存仍有剩余（即部分扣减请求丢失）。
2. **重试失效：** 尽管开启了 Pending Recover 机制，丢失的数据并未被自动恢复。





## **3. 初步排查与假设**

经过初步排查（Jaeger Tracing 及代码审查），排除了 Lua 脚本逻辑错误的可能。目前怀疑问题的根源在于 **高吞吐场景下的进程生命周期管理**：

**假设一：优雅停机失效**

- **分析：** 在高性能环境下，压测结束或容器重启瞬间，服务处理速度极快。
- **疑点：** 当前 `server.go` 的退出逻辑虽然调用了 `grpc.GracefulStop()`，但**未显式等待**后台 `Stream Worker` 协程将内存 Buffer 中的最后积压数据 Flush 到 MySQL。
- **现象关联：** 在本地环境由于 I/O 慢，进程退出过程可能被拉长，侥幸完成了落库；而在 CNB 环境下，容器销毁速度极快，导致内存数据直接丢弃。

**假设二：Redis 持久化与容器销毁的竞态**

- **分析：** 若 Redis AOF 配置为 `everysec`，在极端高并发下容器被强制 Kill，可能存在 1秒内的数据未落盘。

---

【**代码重点索引】** 为了节省您的时间，我将可能出问题的核心逻辑定位到了以下两个文件中：

1. **`server.go` (Main入口)**
   - **Line 130-140:** `main` 函数中的优雅停机逻辑。目前仅调用了 `srv.GracefulStop()`，我怀疑这里没有等待后台 Worker 处理完数据就直接退出了。
2. **`cached_repo.go` (核心业务)**
   - **Line 208 (`startStreamWorker`):** 这是消费 Redis Stream 并写入 MySQL 的核心协程。
   - **Line 239 (`flushBufferToMySQL`):** 这是批量落库的逻辑。
   - **Line 66 (`NewCachedRepo`):** 这里初始化了 CircuitBreaker 和 Worker。