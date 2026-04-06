> #### **测试环境与配置**
>
> - **硬件环境：**Windows WSL2 (模拟 Linux 生产环境)
>
> - **容器限制：**单实例 Pod 配额（模拟 1 Core / 512MB RAM）
>
> - **数据库：**MySQL 8.0 (Gorm ORM) + Redis 7.0 (Go-Redis + Redsync)
>
> - **关键技术栈：**
>   - `SingleFlight`防缓存击穿；
>   - `Async Worker`+`Buffer`写请求削峰填谷；
>   - `CircuitBreaker`熔断降级；
>   - `Reconcile`数据最终一致性对账；
>   - `Lua Script`Redis的原子性扣减。

# 1. 极限吞吐量测试

- **测试命令**

  ```bash
  ghz --insecure \
    --proto ./protos/demo.proto \
    --call hipstershop.ProductCatalogService.ChargeProduct \
    -d '{"product_id": "OLJCESPC7Z", "amount": 1}' \
    --cpus=4 \
    -c 50 -n 100000 \
    localhost:3550
  ```

- **核心数据记录**

  <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-15 224154.png" alt="屏幕截图 2026-01-15 224154" style="zoom: 50%;" />

  - QPS达到25k+时系统依然保持稳定；
  - 平均延迟：1.49ms；
  - P99延迟：3.16ms；
  - 错误率：0%。

- **结论：**在50的并发数量下，瓶颈主要出现在数据库I/O和网络I/O，Redis性能优异。

# 2. 冷启动与防雪崩测试

- **测试背景**：清空 Redis 缓存，模拟服务刚重启或缓存大规模失效，瞬间涌入高并发读取。

- **测试命令**

  ```bash
  ghz --insecure \
    --proto ./protos/demo.proto \
    --call hipstershop.ProductCatalogService.ChargeProduct \
    -d '{"product_id": "OLJCESPC7Z", "amount": 1}' \
    -c 50 -n 500 \
    localhost:3550
  ```

- **核心数据记录**

  <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-16 164746.png" alt="屏幕截图 2026-01-16 164746" style="zoom:50%;" />

  - 并发请求数：500个

  - 实际穿透到MySQL的查询数：1个

  - `SingleFlight`拦截率：
    $$
    \frac{总请求-穿透数}{总请求}\times 100\%=\frac{500-1}{500}\times 100\%=99.8\%
    $$

    - 数据来源验证： 在 500 并发请求发起的冷启动窗口内，通过监控 MySQL `Com_select` 状态变量增量，观测到实际物理查询仅增加 **1** 次。
    - 计算结果： `SingleFlight` 机制成功拦截了 499 个重复请求，拦截率高达 **99.8%**，有效避免了惊群效应导致数据库连接池耗尽。

- **结论：**`SingleFlight`机制成功生效，将500个并发读请求合并为个位数查询，有效防止了 MySQL 被瞬间打垮。

# 3. 混沌工程与故障恢复

**目的**：验证“反脆弱性”和“数据最终一致性”。

- **测试命令**

  ```bash
  ghz --insecure \
  	--proto ./protos/demo.proto \
  	--call hipstershop.ProductCatalogService.ChargeProduct \
  	-d '{"product_id": "OLJCESPC7Z", "amount": 1}' \
      -c 100 --duration 2m --rps 500 \
      localhost:3550
  ```

- **故障注入**：在压测进行中，强制重启 Redis 容器。

- **核心数据记录**

  <img src="C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20260116215642708.png" alt="image-20260116215642708" style="zoom:50%;" />

- **最终数据一致性检验：**

  - MySQL最终扣减量：39893
  - Redis最终扣减量：39893
  - ghz报告成功数：39892

- **结论：**系统通过Redis的AOF模式+异步刷盘写库机制，实现了在Redis宕机的情况下，依然保有最终的数据一致性。

# 4. 长期稳定性测试

- **持续时间：**30分钟

- **负载强度：**2000QPS

- **故障注入：**在压测进行中，多次强制重启Redis和Go服务。

  - 故障执行脚本

    ```bash
    #!/bin/bash
    # chaos.sh
    
    # === 配置区域 ===
    # Redis 容器名
    REDIS_CONTAINER="redis-test"
    # Go 服务容器名
    GO_CONTAINER="product-service-test"
    # ================
    
    echo "开始全链路稳定性破坏脚本 (Redis + Go Service)..."
    echo "测试目标：验证 Redis 重连机制 & Go 服务优雅停机(Buffer刷盘)能力"
    
    for i in {1..5}
    do
        echo "----------------------------------------------------"
        echo "[ROUND $i] 混沌测试开始 - $(date)"
    
        # --- 场景 1: 重启 Redis (测试断连与重试) ---
        echo "[$(date)] 🔥 正在重启 Redis 容器 ($REDIS_CONTAINER)..."
        docker restart $REDIS_CONTAINER
        echo "[$(date)] Redis 重启指令已发送，等待 30 秒让应用恢复/重连..."
        sleep 30
    
        # --- 场景 2: 重启 Go 服务 (测试优雅停机与Buffer落盘) ---
        echo "[$(date)] ☠️ 正在重启 Go 服务容器 ($GO_CONTAINER)..."
        # docker restart 默认发送 SIGTERM 信号，会触发你的 ctx.Done() 逻辑
        # 默认等待 10秒
        docker restart $GO_CONTAINER
        echo "[$(date)] Go 服务重启指令已发送 (预期触发 FlushBuffer)..."
    
        # --- 等待下一轮 ---
        echo "[$(date)] 本轮结束，系统冷静期 5 分钟..."
        sleep 300
    done
    
    echo "所有测试循环结束。"
    ```

- **资源监控数据：**

  - Goroutine数量：
    - 初始：约10个
    - 结束：约10个
    - *结论：无Goroutine泄露。*

  - 内存占用：
    - 峰值：不超过400MB
    - 均值：390MB
    - *结论：内存波动平稳，不存在OOM风险。*
  - 错误日志：
    - 测试期间共出现0次`panic`和`fatal`错误。

- **测试命令**

  ```bash
  ghz --insecure \
  	--proto ./protos/demo.proto \
      --call hipstershop.ProductCatalogService.ChargeProduct \
      -d '{"product_id": "OLJCESPC7Z", "amount": 1}' \
      -c 10   --rps 2000   --duration 30m \
      localhost:3550
  ```

- **核心数据记录**

  <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-16 223221.png" alt="屏幕截图 2026-01-16 223221" style="zoom: 50%;" />

  <img src="C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20260116224443270.png" alt="image-20260116224443270" style="zoom:50%;" />

- **最终数据一致性检验：**

  - MySQL最终扣减量：3589877
  - Redis最终扣减量：3589877
  - ghz报告成功数：3589872

- **结论：**系统能够在高并发的情况下长时间稳定运行，具备容灾恢复的能力，且仍可确保最终数据一致性。

# 5. 遇到的核心问题与解决方案

1. **库存初始化失败，压测结果报错**

   - 报错输出

     ```bash
      rpc error: code = Internal desc = failed to charge product: Stock not initialized
     ```

   - **代码改进**

     - 在`lazy load`部分增加重试循环，防止`SingleFlight`中单个请求读取失败的情况出现。

       ```go
       // 库存未初始化，合并查数据库请求
       // 多次尝试防止lazy load失败
       for i := 0; i < 3; i++ {
           _, err, _ = c.sf.Do("load_stock:"+productId, func() (interface{}, error) {
               // 防止lazy load与reconcile冲突
               if c.rdb.Exists(ctx, stockKey(productId)).Val() > 0 {
                   c.log.Infof("[LoadStock] Key %s already exists, skipping overwrite", productId)
                   return nil, nil
               }
       
               product, err := c.next.GetProduct(ctx, productId)
               if err != nil {
                   c.log.Errorf("[LoadStock] failed to get product %s from mysql: %v", productId, err)
                   return nil, err
               }
       
               // lazy load回redis
               ...
           })
       
           if err == nil {
               break
           }
           c.log.Warnf("[LoadStock] Retry %d loading stock due to error: %v", i, err)
       }
       ```

2. **当MySQL库存小于Redis时数据无法修复**

   - 错误情况：进行`reconcile`对账时，若遇到MySQL库存量小于Redis库存量，则不进行改动，且保留`Dirty List`；

   - **代码改进**

     - 选择较小的MySQL数据作为真实数据源，将MySQL库存量重新写回Redis，防止超卖。

       ```go
       // 核对数据库的库存和redis库存是否一致
       if mStock > rStock {
           ...
       } else if mStock < rStock {
           // 增加当sql库存更少时的处理逻辑（强行将sql的同步至redis防止超卖）
           err := c.rdb.Set(ctx, stockKey(productId), mStock, time.Hour*24).Err()
           if err != nil {
               atomic.AddUint64(&c.reconcileFailTotal, 1)
               return fmt.Errorf("failed to force update redis: %w", err)
           }
           c.clearDirtyIfVerMatch(ctx, productId, verBefore)
           atomic.AddUint64(&c.reconcileSkipTotal, 1)
       } else {
           atomic.AddUint64(&c.reconcileSkipTotal, 1)
       }
       ```

3. *Redis重启后数据丢失，导致必须重新进行`lazy load`，同时与worker刷盘进程冲突*

   - **错误示意图**

     ![product_catalog-lazy load vs worker.drawio](C:\Users\86133\Desktop\学习\dio图表\MicroService\product_catalog-lazy load vs worker.drawio.svg)

   - 配置文件改进

     开启Redis的AOF持久化机制，避免重启后Redis数据丢失，导致`lazy load`读取旧的MySQL数据后回写到Redis。

     ```yaml
     redis:
         image: redis:7-alpine
         container_name: redis-test
         command: redis-server --appendonly yes # 开启 AOF 持久化，模拟真实环境
         ports:
           - "6380:6379"
         volumes:
           - /home/dantalion/redis_data:/data
     ```


---

# minikube环境与可视化

## 核心压测数据

1. **极限吞吐量测试**

   <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-18 191820.png" alt="屏幕截图 2026-01-18 191820" style="zoom:50%;" />

   - 最大RPS：2000；

   - **数据库写入频率：**稳定在 **2 TPS**；

   - **削峰效果：**在压测期间，成功把10万次写库请求聚合为96次MySQL批量更新。

     <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-18 195143.png" alt="屏幕截图 2026-01-18 195143" style="zoom:50%;" />

2. **客户端与服务端延迟差异分析**

   在高并发压测中，观测到客户端 (`ghz`) 报告的 P99 延迟约为 **150ms**，而服务端 (`Jaeger`) 报告的 P99 仅为 **50ms** 左右。

   <img src="C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-18 200210.png" alt="屏幕截图 2026-01-18 200210" style="zoom:50%;" />

   ![屏幕截图 2026-01-18 200240](C:\Users\86133\Desktop\学习\dio图表\MicroService\屏幕截图 2026-01-18 200240.png)

   - Jaeger Trace 显示，一旦请求进入业务处理函数，耗时极短。

     <img src="C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20260118200345599.png" alt="image-20260118200345599" style="zoom:50%;" />

     - 服务端视角显示，实际业务处理逻辑（含 Redis 交互）仅耗时 50ms (含高负载下的调度损耗)。