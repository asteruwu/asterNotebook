# 背景与目标

## 项目背景

在典型电商场景中，**库存系统同时面临三类压力**：

1. **写入压力极高**
   - 秒级峰值 QPS 可达数千到数万
   - MySQL 无法承受 1:1 的实时扣减写入
2. **读热点明显**
   - 少量热门 SKU 占据绝大部分流量
   - 缓存击穿、雪崩风险显著
3. **系统必须可恢复**
   - Worker / Pod 随时可能重启
   - 不能因异步组件失败导致库存永久不一致

## 设计目标

- 支持 **日常高并发**（非秒杀）

- Redis 承担实时库存真相
- MySQL 承担最终持久化
- 不引入 MQ / 分布式事务等重型组件
- 允许短暂不一致，但 **不允许语义丢失**
- 不追求强一致 / exactly-once

# 系统整体架构概览

<img src="../../../dio图表/MicroService/product_catalog-高并发读写架构设计.drawio.svg" alt="product_catalog-高并发读写架构设计.drawio" style="zoom:120%;" />

| 存储   | 角色       | 一致性               |
| ------ | ---------- | -------------------- |
| Redis  | 实时真相源 | 强一致（单线程 Lua） |
| MySQL  | 持久副本   | 最终一致             |
| Worker | 异步桥梁   | 可失败               |

# 架构演进记录

1.  **基础异步写入**
   - **核心思路：** 流量来了先写 Redis，然后丢进一个 Go Channel，后台起一个 Worker 一个个取出来写 MySQL。

     - **架构图：** `Request -> Redis (Lua) -> Channel -> Worker -> MySQL`

     - **初衷：** 解决 MySQL 抗不住高并发扣减的问题。

   - **缺点**：MySQL 的写入依然是 1:1 的（QPS 多少，TPS 就多少）。如果并发是 1万，MySQL 还是要承受 1万次 Update，虽然是异步的，但数据库依然会爆，且 Channel 很快会满。

2.  **引入分布式锁**

   - **核心思路：** 为了保证绝对的数据安全，引入 Redsync（Redlock），加上看门狗（Watchdog）、Token 校验、重试机制。
   - **初衷：** 担心并发冲突，担心数据不一致，追求强一致性。
   - **分析**：Redis 的 Lua 脚本本身就是原子执行的（单线程特性），在扣减库存这个单一场景下，Lua 的安全性 = 分布式锁。引入 Redsync 反而增加了 2 次网络 RTT（加锁+解锁），导致性能下降一半。

3.  **纯缓存模式**

   - **核心思路：** 高峰期彻底断开 MySQL 连接，只写 Redis 和 Redis List（记录日志）。等活动结束，再写个脚本慢慢把数据同步回数据库。
   - **初衷：** 彻底消除数据库瓶颈，追求理论上的最高吞吐量。
   - **缺点：**
     - **适用性受限**：这是“双11秒杀”的打法。
     - **被否决原因**：不适合“日常高并发”场景。数据落库延迟太大（小时级），风险过于集中在 Redis，一旦 Redis 宕机且持久化没跟上，所有订单全丢。且运营无法实时看到数据。

4.  **读写分离 + 写合并** | 最终定稿

   - **写路径**
     - **策略：** **“漏斗模型” + “内存聚合”**。
     - **流程：** `Traffic (10k QPS)` -> `Redis Lua` -> `Channel` -> `1 Single Worker (Map Buffer)` -> `Ticker (500ms)` -> `MySQL (2 TPS)`。
     - **亮点：**
       - **单线程 Worker**：利用 Go 协程的私有变量（Map），无锁处理高并发聚合。
       - **削峰填谷**：把 10,000 次数据库写操作，在内存里合并成几十次 SQL Update。
       - **原子更新**：MySQL 层使用 `UPDATE stock = stock - ?`，保证即使覆盖也不丢运营的补货数据。
   - **读路径**
     - **策略：** **Cache-Aside (旁路缓存) + Lazy Load**。
     - **流程：** `Get Stock` -> `Redis Miss (-1)` -> `SingleFlight` -> `Load from DB` -> `Set Redis` -> `Retry Deduct`.
     - **亮点：**
       - **SingleFlight**：完美防御热点商品的缓存击穿。
       - **Lazy Load**：解决了“全量预热”内存占用过大的问题，支持海量商品。
       - **强制回源**：加载逻辑走 `next.GetProduct`，避免逻辑死循环。

# 最终架构设计

## 写路径

- **原子扣减**：使用 **Lua 脚本** 封装 `Check -> Decr -> DirtyMark -> VersionIncr`。保证扣减库存和标记脏数据（Dirty Set）的原子性。

  ```go
  const LuaDeductStock = `
      local stockKey = KEYS[1]
      local verKey = KEYS[2]
      local dirtySet = KEYS[3]
  
      local productId = ARGV[1]
      local amount = tonumber(ARGV[2])
  
      local current = tonumber(redis.call('get', stockKey))
  
      if current == nil then
          return {-1, 0} -- Key不存在（需要重载）
      end
  
      if current >= amount then
          redis.call('decrby', stockKey, amount)
          local newVer = redis.call('incr', verKey)
          redis.call('sadd', dirtySet, productId)
          return {1, newVer} -- 成功
      else
          return {0, 0} -- 库存不足
      end
  `
  ```

- **内存聚合**：单线程 Worker 监听 Channel，将同商品的扣减请求在 `map[string]int32` 中累加。

  ```go
  for {
      select {
      // task聚合 记录增量变化
      case task := <-c.syncCh:
          buffer[task.ProductId] += task.Amount
      ...
  ```

- **定时落库**：通过 `Ticker` (500ms) 定时将 Map 中的聚合结果批量更新至 MySQL (`UPDATE stock = stock - ?`)。

  ```go
      // 异步写库，刷新增量变化
      case <-ticker.C:
          if len(buffer) > 0 {
              c.log.Infof("[Async Worker] Syncing stock to MySQL")
              c.flushBufferToMySQL(ctx, buffer)
              buffer = make(map[string]int32)
          }
  ```

## 读路径

- **按需加载**：Redis 仅缓存热点数据，冷数据过期自动释放。

  ```go
  // 聚合相同的读请求
  result, err, shared := c.sf.Do(key, func() (interface{}, error) {
      product, err := c.next.GetProduct(ctx, id)
      if err != nil {
          c.log.Errorf("[GetProduct] failed to get product %s from mysql: %v", id, err)
          return nil, err
      }
  
      data, _ := json.Marshal(product)
      ttl := 10*time.Minute + time.Duration(rand.Intn(60))*time.Second
      if err := c.rdb.Set(ctx, key, string(data), ttl).Err(); err != nil {
          c.log.Errorf("[GetProduct]failed to write cache for redis key %s: %v", key, err)
      }
  
      return product, nil
  })
  ```

- **SingleFlight**：使用 `singleflight` 机制，确保当热点 Key 失效时，瞬间的万级并发请求中，只有 **1 个** 请求穿透到 MySQL，其余请求共享结果。

  ```go
  result, err, shared := c.sf.Do(key, func() (interface{}, error) { ... }
  ```

  

# 容灾与高可用设计

本架构通过 **"Crash Safety"** 机制，解决了异步写入可能导致的数据丢失问题。

## 数据一致性保障

- **问题**：Pod 意外宕机（OOM/Kill）导致内存 Buffer 中的聚合数据丢失。

- **方案**：**Dirty Set + Startup Reconcile**。

  - **Dirty Set**：Redis 修改库存时，强制将 `ProductId` 写入 `product:dirty` 集合。

    ```lua
    if current >= amount then
        redis.call('decrby', stockKey, amount)
        local newVer = redis.call('incr', verKey)
        redis.call('sadd', dirtySet, productId) -- 写入product:dirty
        return {1, newVer} -- 成功
    else return {0, 0} -- 库存不足
    end
    ```

  - **Reconcile**：Pod 重启时，优先运行对账程序，扫描 Dirty Set，强制将 Redis 的最新库存覆盖至 MySQL，实现最终一致性。

    ```go
    ids, next, err := c.rdb.SScan(ctx, redisDirtySetKey, cursor, "", 200).Result()
    ...
    for _, productId := range ids {
        atomic.AddUint64(&c.reconcileItemsTotal, 1)
        if err := c.reconcileOneProduct(ctx, productId); err != nil {
            atomic.AddUint64(&c.reconcileFailTotal, 1)
            c.lastReconcileErrorText.Store(err.Error())
            c.log.Errorf("[Reconcile] Failed to reconcile product %s: %v", productId, err)
        }
    }
    ```

    ```go
    if mStock > rStock {
        ok, msg := c.next.ChargeProduct(ctx, productId, int32(mStock-rStock))
        if !ok {
            return fmt.Errorf("mysql deduct diff failed: %s", msg)
        }
        atomic.AddUint64(&c.reconcileFixTotal, 1)
    }
    ```

## 并发启动竞争防护

- **问题**：K8s 滚动更新导致多 Pod 同时启动，并发修复同一商品导致数据错乱。

- **方案**：**分布式锁 (Distributed TryLock)**。

  - 启动对账时，使用 Redis 分布式锁抢占商品修复权。

  - 采用 `TryLock` 模式：抢不到锁直接跳过（说明有其他 Pod 在修），极大提升集群启动时的修复效率，避免惊群效应。

    ```go
    // 非阻塞锁，防止写竞争的同时并行写
    mutex := c.rs.NewMutex("lock:reconcile:" + productId)
    if err := mutex.TryLockContext(ctx); err != nil {
        atomic.AddUint64(&c.reconcileSkipTotal, 1)
        c.log.Debugf("[Reconcile] Skip %s, locked by others", productId)
        return nil
    }
    defer mutex.UnlockContext(ctx)
    ```

## 严格隔离恢复期与工作期

在具备 **异步写库 + 崩溃恢复（reconcile）** 的系统中，如果**恢复流程与正常增量流程同时运行**，极易引发以下风险：

- 同一 product 的库存被：
  - 恢复流程修复一次
  - 正常 worker 再扣减一次
- 导致 **重复写入 / 二次扣库存**
- 即使单次逻辑正确，**组合执行仍可能破坏一致性**。

因此系统通过 **启动顺序强约束** 来保证阶段隔离：

```go
go func() {
    s.reconcileDirtyOnStartup(ctx)
    s.startStockSyncWorker(ctx)
}()
```

## 优雅停机

- **机制**：监听 `SIGTERM` 信号，在 Context 取消时强制执行最后一次 `FlushBuffer`，尽可能减少数据丢失窗口。

  ```go
  case <-ctx.Done():
      c.log.Infof("[Async Worker] Shutting down")
      c.flushBufferToMySQL(ctx, buffer)
      return
  ```

# 可观测性设计

*待补充详细测试报告。*

- **Worker内部指标暴露**

  ```go
  func (c *cachedRepo) GetWorkerStatus() WorkerStatus {
  	errText, _ := c.lastReconcileErrorText.Load().(string)
  
  	return WorkerStatus{
  		SyncQueueLen:      len(c.syncCh),
  		SyncQueueCap:      cap(c.syncCh),
  		LastFlushUnixNano: atomic.LoadInt64(&c.lastFlushUnixNano),
  		FlushSuccessTotal: atomic.LoadUint64(&c.flushSuccessTotal),
  		FlushFailTotal:    atomic.LoadUint64(&c.flushFailTotal),
  
  		ReconcileRunsTotal:     atomic.LoadUint64(&c.reconcileRunsTotal),
  		ReconcileItemsTotal:    atomic.LoadUint64(&c.reconcileItemsTotal),
  		ReconcileFixTotal:      atomic.LoadUint64(&c.reconcileFixTotal),
  		ReconcileSkipTotal:     atomic.LoadUint64(&c.reconcileSkipTotal),
  		ReconcileFailTotal:     atomic.LoadUint64(&c.reconcileFailTotal),
  		LastReconcileUnixNano:  atomic.LoadInt64(&c.lastReconcileUnixNano),
  		LastReconcileErrorText: errText,
  	}
  }
  ```

  - Channel 长度

  - flush 成功 / 失败次数

  - reconcile 执行 / 修复 / 跳过 / 失败次数

# 已知限制

- MySQL < Redis 的库存修复（无法补库存）
- exactly-once 语义
- 自动全量 reconcile
- 秒杀级极端场景

