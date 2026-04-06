# 基本数据结构

## String

- **概念**
  - 最基本的数据类型，可以存储**文本、整数或序列化对象**（如 JSON）。最大容量 512MB。
- **使用场景与优势**
  - **缓存功能**：存储 Session、Token、页面数据或对象 JSON。
  - **计数器**：利用原子递增特性记录访问量 (PV)、点赞数。
  - **分布式锁**：利用 `SETNX` (Set if Not Exists) 实现互斥锁。

- **常用命令**

  - `SET key value`：存入一个值。

  - `GET key`：读取一个值。

  - `INCR key`：将存储的数字值加 1（原子操作）。

  - `EXPIRE key seconds`：设置键的过期时间（秒）。

  - `SETNX key value`：只有键不存在时才设置值（用于锁）。

- **`go-redis`相关函数**

  - `client.Set(ctx, "key", "value", 0).Err()` (0 表示永不过期)

  - `value, err := client.Get(ctx, "key").Result()`
  - `client.Incr(ctx, "counter")`
  - `client.SetNX(ctx, "lock_key", "value", 10*time.Second)`

## Hash

类似于 Go 语言中的 `map[string]string`，但它作为一个整体存储在一个 Redis Key 下。

- **概念**

  - 一个 String 类型的 Field 和 Value 的映射表。
  - 特别适合存储对象。

- **使用场景与优势**

  - **存储对象详情**：如用户信息（ID, Name, Age）、商品详情。

  - **优势**：相比于将整个对象序列化为 String 存储，Hash 可以**独立读取或修改**对象中的某个字段，节省网络流量和内存开销。
    - **聚合性**：数据归属在一个 Key (`user:1001`) 下，逻辑清晰。
    - **原子字段修改**：不需要读取整个对象，也不需要操作其他字段。
    - **内存更优**：Redis 对 Hash 结构做了专门的内存压缩优化。

- **常用命令**

  - `HSET key field value`：设置哈希表中指定字段的值。

  - `HGET key field`：获取哈希表中指定字段的值。

  - `HGETALL key`：获取哈希表中所有的字段和值。

  - `HINCRBY key field increment`：为哈希表中的字段值加上指定增量。

- **`go-redis`相关函数**

  - `client.HSet(ctx, "user:1001", "name", "John")`

  - `val, err := client.HGet(ctx, "user:1001", "name").Result()`

  - `all, err := client.HGetAll(ctx, "user:1001").Result()` (返回 `map[string]string`)

  - `client.HIncrBy(ctx, "user:1001", "points", 10)`

## List

简单的字符串列表，按照插入顺序排序。

- **概念**

  - 底层通常是双向链表。
  - 支持从头部 (Left) 或尾部 (Right) 添加和弹出元素。

- **使用场景与优势**

  - **消息队列**：简单的生产者-消费者模型（Producer `RPUSH`, Consumer `LPOP`）。

  - **最新消息/时间线**：比如存储用户最近浏览的 10 个商品 ID。

  - **阻塞队列**：利用 `BLPOP` 实现，当队列为**空**时，消费者会**阻塞等待**新消息，避免轮询浪费 CPU。

  > [!NOTE]
  >
  > 当客户端发起 `BLPOP` 时，如果没数据，Redis 服务端会把这个连接标记为“阻塞状态”，并挂起该连接。客户端程序的线程也会进入**Sleep 状态**（由操作系统管理，移出 CPU 运行队列）。此时，它**不占用任何 CPU 时间片**。一旦有数据写入，Redis 会唤醒该连接，客户端线程恢复运行。

- **常用命令**

  - `LPUSH key value` / `RPUSH key value`：从左/右推入元素。
  - `LPOP key` / `RPOP key`：从左/右弹出元素。
  - `LRANGE key start stop`：获取指定范围的元素（0 -1 表示获取全部）。
  - `BLPOP key timeout`：阻塞式弹出（队列为空则等待）。

- **`go-redis`相关函数**

  - `client.LPush(ctx, "queue", "task1")`

  - `client.RPush(ctx, "queue", "task2")`
  - `val, err := client.LPop(ctx, "queue").Result()`
  - `items, err := client.LRange(ctx, "queue", 0, -1).Result()`

  > [!NOTE]
  >
  > `-1`为结束索引，表示倒数第一个元素。

## Set

String 类型的无序集合。

- **概念**

  - **无序性**：元素没有顺序。
  - **唯一性**：集合中不能出现重复的数据。

- **使用场景与优势**

  - **标签系统**：给用户打标签（如 "music", "tech"），自动去重。
  - **共同好友/推荐系统**：利用集合运算（交集、并集）计算两个用户的共同关注。
  - **抽奖活动**：利用 `SRANDMEMBER` 随机获取元素。

- **常用命令**

  - `SADD key member`：添加元素。

  - `SISMEMBER key member`：判断元素是否存在（效率极高）。

  - `SMEMBERS key`：返回集合中所有元素。

  - `SINTER key1 key2`：求两个集合的交集。

- **`go-redis`相关函数**

  - `client.SAdd(ctx, "tags:1", "music", "code")`

  - `isMember, err := client.SIsMember(ctx, "tags:1", "code").Result()`
  - `intersect, err := client.SInter(ctx, "user1:friends", "user2:friends").Result()`

## ZSet

String 类型的有序集合。

- **概念**

  - 每个元素都会关联一个 **double 类型的分数 (Score)**。
  - 元素是唯一的，但分数可以重复。
  - 底层使用**跳跃表 (Skip List)** 和哈希表实现，查询效率高。

  > [!NOTE]
  >
  > 哈希表存储 `Member -> Score` 的映射，能够实现时间复杂度为$$O(1)$$的**精准点查**；
  >
  > 跳跃表存储按 Score 排序后的元素，并且在链表之上加了“多级索引”，实现了类似**二分查找**的效果，时间复杂度为$$O(\log n)$$。

- **使用场景与优势**

  - **排行榜**：游戏分数榜、视频热度榜（Score 存分数/热度，Member 存 ID）。

  - **带权重的消息队列**：按优先级处理任务。

  - **范围查询**：比如查找分数在 80-100 之间的用户。

- **常用命令**

  - `ZADD key score member`：添加元素并设置分数。

  - `ZRANGE key start stop [WITHSCORES]`：按分数从低到高返回指定排名的元素。

  - `ZREVRANGE key start stop`：按分数从高到低返回（常用的排行榜逻辑）。

  - `ZSCORE key member`：获取指定元素的分数。

- **`go-redis`相关函数**

  - `client.ZAdd(ctx, "leaderboard", redis.Z{Score: 100, Member: "UserA"})`

  - `rank, err := client.ZRevRangeWithScores(ctx, "leaderboard", 0, 9).Result()` (获取前 10 名)

  - `score, err := client.ZScore(ctx, "leaderboard", "UserA").Result()`

---

## 原子性

指的是一个操作或一组操作，要么**全部完成**，要么**全部不完成**。它就像一个**原子**一样，是**不可分割**的最小工作单元。

- **核心要点**

  - **不可分割性**：在原子操作执行过程中，不允许被中断。

  - **排他性**：在操作执行过程中，其他进程或线程看不到中间状态，只能看到操作前或操作后的最终状态。

  - **并发控制**：在多线程或分布式环境中，原子性是保证数据正确性的基础，它避免了因为并发读写导致的**数据不一致性**和**竞态条件**。

- **Redis体现**
  - **单个命令的原子性**：由于 Redis 是单线程的，它会**顺序执行**每个客户端的命令。一个命令从开始到结束不会被其他命令打断。例如 `INCR` (自增) 是原子的，不必担心两个客户端同时执行 `INCR` 导致最终结果错误。
  - **多命令的原子性**：当我们需要执行一系列相关联的命令时，就需要使用 **WATCH/MULTI/EXEC 事务** 或 **Lua 脚本** 来确保这一系列操作的原子性。

# 高级特性 | 持久化 | 内存管理

## 高级数据结构

### Bitmaps

- **概念**
  - **本质**：不是独立的数据类型，而是基于 **String** 类型的按位操作。
  - **存储模型**：可以将其视为一个极长的二进制数组（Bit Array），下标是偏移量（Offset），值为 0 或 1。
  - **空间占用**：极其节省。存储 1 亿个用户的布尔状态（如在线/离线）仅需约 12MB 内存。
  - **寻址方式**：通过 Offset 定位，时间复杂度为$$O(1)$$。

- **使用场景与优势**

  - **场景**：

    - **二值状态统计**：用户签到（签了/没签）、在线状态（在线/离线）、消息已读（已读/未读）。
    - **活跃度统计 (DAU/MAU)**：配合 `BITOP` 进行逻辑运算。

  - **优势**：

    - **省内存**：对比 `Set` 或 `Hash`，存储海量 Boolean 数据时优势巨大。

    - **计算快**：位运算效率极高。

- **常用命令**

| **命令**   | **描述**                    | **示例**                                               |
| ---------- | --------------------------- | ------------------------------------------------------ |
| `SETBIT`   | 设置指定偏移量的值 (0 或 1) | `SETBIT key offset value`                              |
| `GETBIT`   | 获取指定偏移量的值          | `GETBIT key offset`                                    |
| `BITCOUNT` | 统计被设置为 1 的位的个数   | `BITCOUNT key [start end]` (注意 start/end 是字节索引) |

- **`go-redis`相关函数**

  - `rdb.SetBit(ctx, key, offset, value)`

  - `rdb.GetBit(ctx, key, offset)`

  - `rdb.BitCount(ctx, key, &redis.BitCount{Start: 0, End: -1})`

### HyperLogLog 

- **概念**

  - **本质**：一种**概率数据结构**，用于海量数据的**基数统计**（去重后的数量）。
  - **原理**：利用哈希函数的均匀分布特性，通过统计哈希值二进制表示中“前导零”的最大数量，来估算数据规模（伯努利试验 + 调和平均去噪）。
    - **基数统计实现机制**
      1. 使用一个哈希函数，将任何输入都变成一串二进制数字，且二进制数字每一位输出0和1的概率均相等；
      2. 观察“最长连续的前导零”，对应**“最罕见的情况”**，越长则基数大的概率越大；
      3. **平摊概率**：16384个桶，把每个数据分流到不同的桶中（基于哈希值分流）；
      4. **去重**：每个桶**单独统计**该桶内的“最长连续零”；
      5. **抗干扰**：使用调和平均把所有桶的数据合起来算一个总数，得到最终估算的基数。
      
      <img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis.drawio.svg" alt="Redis.drawio" style="zoom:120%;" />
  - **特点**：

    - **不存数据**：只存特征，无法取回原数据。

    - **固定大小**：无论存多少数据，占用内存恒定（稠密模式下约 12KB）。

    - **有误差**：标准误差约为 0.81%。

- **使用场景与优势**

  - **场景**：

    - **UV 统计**：统计网站每天有多少独立访客。
    - **搜索词统计**：统计用户搜了多少个不同的关键词。
    - **大流量去重计数**：不需要精确到个位的大规模计数。

  - **优势**：

    - **内存极度节省**：存 10 亿个 IP，HLL 只要 12KB；用 Set 可能需要几 GB。

  - **劣势**：

    - 结果是近似值（不适合金融场景）。

    - 无法判断某个具体元素是否存在（不能做 `IsMember` 操作）。

- **常用命令**

  | **命令**  | **描述**                    | **示例**                          |
  | --------- | --------------------------- | --------------------------------- |
  | `PFADD`   | 添加一个或多个元素          | `PFADD key element [element ...]` |
  | `PFCOUNT` | 返回基数的估算值            | `PFCOUNT key [key ...]`           |
  | `PFMERGE` | 合并多个 HLL 到一个新的 Key | `PFMERGE dest source1 source2`    |

- **`go-redis`相关函数**
  - `rdb.PFAdd(ctx, key, els...)`
  - `rdb.PFCount(ctx, key...)`

## Lua脚本

**特点**

- **原子性**：Redis 会将整个 Lua 脚本作为一个整体执行，中间不会被其他客户端的命令插入。这解决了“竞态条件”问题。
- **减少网络开销**：可以将多个步骤逻辑打包发送一次，减少 RTT (Round Trip Time)。

### 变量与作用域

 永远使用 `local`，除非真的需要全局变量。

```lua
-- 定义变量
local age = 20        -- 整数
local name = "Gemini" -- 字符串
local is_ok = true    -- 布尔值
local nothing = nil   -- 类似于 Go 的 nil

-- 字符串拼接（注意：不是 + 号，是 ..）
local full_info = name .. " is " .. age
print(full_info) -- 输出: Gemini is 20
```

### 数据结构

只有一种复杂数据结构叫 `table`。它既是数组（Slice），也是哈希表（Map）。

> [!CAUTION]
>
> 数组下标从1开始

```lua
-- 1. 作数组用 (Array/Slice)
local skills = {"Go", "Redis", "Linux"}
print(skills[1]) -- 输出: Go (注意不是0)

-- 2. 作字典用 (Map)
local user = {
    id = 1001,
    role = "SRE",
    ["active_status"] = true -- 如果key有特殊字符，用 ["key"]
}
print(user.role) -- 输出: SRE
print(user["role"]) -- 也可以这样取
```

### 控制流程

> [!CAUTION]
>
> 在条件判断中，只有 `false` 和 `nil` 是假，**数字 0 是真（True）**

```lua
local score = 85

-- 条件判断
if score >= 90 then
    print("A")
elseif score >= 60 then
    print("Pass")
else
    print("Fail")
end

-- 循环 (遍历数组)
-- ipairs 用于遍历类似于数组的连续 table
local list = {"a", "b", "c"}
for index, value in ipairs(list) do
    print(index, value)
end

-- 循环 (遍历 Map)
-- pairs 用于遍历键值对
local map = {name="G", age=2}
for k, v in pairs(map) do
    print(k, v)
end
```

### 函数

支持多返回值。

```lua
local function calc(a, b)
    return a + b, a - b
end

local sum, diff = calc(10, 5)
print(sum, diff) -- 15, 5
```

---

### 在Go中调用Lua

场景：给 API 接口做限流，每分钟只能访问 10 次。

1. **定义Lua脚本**

   ```go
   const rateLimitScript = `
   local key = KEYS[1]
   local limit = tonumber(ARGV[1])
   local expire = tonumber(ARGV[2])
   
   local current = tonumber(redis.call('GET', key) or 0)
   
   if current < limit then
   	local new = redis.call('INCR', key)
   
   	if new == 1 then
   		redis.call('EXPIRE', key, expire)
   	end
   
   	return 1
   else
   	return 0
   end
   `
   ```

   - 从函数注入的参数中获得`key`、`limit`和`expire`；
   - 取出`key`的当前值，存储为`current`；未赋值的话则取0；
   - 如果没有达到`limit`则进行原子化操作，给`key`值+1，且Lua脚本整体返回1；
   - 如果正好为1（说明是该时段内的第1次访问），给`key`添加过期时间；
   - 如果超过`limit`则Lua脚本整体返回0。

2. **验证并发控制**

   此处略去了与Redis建立连接。

   > 创建`key`并清理环境

   ```go
   key := "api_limit:user:1001"
   rdb.Del(ctx, key)
   ```

   > 模拟并发请求，注入`limit`和`expire`

   ```go
   var wg sync.WaitGroup
   
   total_requests := 20
   limit := 10
   expire := 60
   
   for i := 0; i < total_requests; i++ {
       wg.Add(1)
       go func(reqID int) {
           defer wg.Done()
           // 通过rdb.Eval(ctx, LuaScript, key, arg)来载入Lua脚本、注入相关变量
           // Result方法会得到Lua脚本的返回值
           result, err := rdb.Eval(ctx, rateLimitScript, []string{key}, limit, expire).Result()
           if err != nil {
               fmt.Printf("[Req %d] Redis Error: %v\n", reqID, err)
               return
           }
   
           // 根据Lua脚本返回值判断请求是否成功
           if result.(int64) == 1 {
               fmt.Printf("[Req %d] Success\n", reqID)
           } else {
               fmt.Printf("[Req %d] Failed\n", reqID)
           }
       }(i)
   }
   wg.Wait()
   
   fmt.Println("------------------------------------------------")
   val, _ := rdb.Get(ctx, key).Result()
   ttl, _ := rdb.TTL(ctx, key).Result()
   fmt.Printf("最终 Redis 状态 -> Key值: %s, 剩余过期时间: %v\n", val, ttl)
   ```

## RDB与AOF

### RDB | 快照模式

- **工作原理**
  - 在指定的时间间隔内，如果满足一定条件（比如“60秒内至少有1000个键被修改”），Redis 就会**把内存中的所有数据生成一个二进制文件**（默认为 `dump.rdb`）保存在硬盘上。

- **触发方式**

  - `save`：会阻塞主线程，直到文件生成完毕。**生产环境禁止使用**

  - `bgsave` (Background Save)：后台异步保存。

    当执行 `bgsave` 时，Redis 并不是把主线程停下来慢慢写文件，而是利用了 Linux 的 `fork()` 系统调用。

    - **Fork**：Redis 主进程（Parent）调用 `fork()` 生成一个子进程（Child）。
    - **共享内存**：子进程和父进程共享同一块物理内存空间。子进程负责把内存数据写入 RDB 文件。
    - **COW （写时复制）**：
      - **读操作**：父子进程互不影响。
      - **写操作**：当主进程（Parent）要修改某个数据页（Page）时，操作系统会将该页**复制**一份副本给主进程修改，而子进程**继续读取原来的旧数据页**写入硬盘。

> COW和**数据一致性**

- 忽略快照期间写入的新数据，获得一份**逻辑绝对正确**、互相关联的数据副本；
- **隔离**主进程和子进程，子进程拥有了一个“只读视图”，而主进程可以继续全速处理读写，互不干扰。

### AOF | 记账模式

- **工作原理**
  - Redis 每执行一条写命令（如 `SET key value`），就把它追加到 AOF 文件的末尾。使用AOF恢复数据时，Redis 重新执行一遍文件里的命令。

- **AOF重写**
  - AOF 文件会越写越大；
    - 比如对 `count` 加了 100 次，文件里就有 100 条 `INCR`，但实际只需要一条 `SET count 100`；
  - Redis 在后台自动执行重写，剔除冗余命令，生成一个新的、更小的 AOF 文件。

| **特性**       | **RDB**                           | **AOF**            |
| -------------- | --------------------------------- | ------------------ |
| **文件大小**   | 小（二进制压缩）                  | 大（文本协议）     |
| **恢复速度**   | **极快**                          | 慢（需重放命令）   |
| **数据安全性** | 低（丢一段时间）                  | **高**（丢 1 秒）  |
| **优先级**     | 低（AOF 开启时，优先用 AOF 恢复） | **高**             |
| **系统资源**   | 消耗 CPU/内存 (Fork)              | 消耗 IO (持续写盘) |

### 混合持久化

- **原理：** 当 AOF 重写时，Redis 不再是把内存数据写成 AOF 命令，而是：

  1. 先将当前的内存数据以 **RDB (二进制)** 格式写入 AOF 文件的开头。

  2. 重写期间新产生的写命令，继续以 **AOF (文本)** 格式追加到文件末尾。

     ```
     [ RDB 二进制数据 (快速恢复) ] + [ AOF 增量日志 (保证最新) ]
     ```

- **优势**
  - **秒级恢复**：绝大部分数据通过加载 RDB 部分快速完成。
  - **数据安全**：RDB 之后的增量数据由 AOF 保证，丢失极少。

## 内存管理

- **范围**
  - `allkeys`：从 Redis 里**所有**的 Key 中进行淘汰。——纯缓存
  - `volatile`：只从**设置了过期时间 (TTL)** 的 Key 中进行淘汰。——缓存+存储
- **算法**
  - **LRU** | Least Recently Used：最近最少使用；
  - **LFU** | Least Frequently Used：使用频率最低；
  - **Random**：随机；
  - **TTL**：剩余寿命最短。

### 不淘汰

- **`noeviction`：默认配置**

  - **行为**：内存满了，再有**写请求**（涉及申请内存的操作）进来，直接**报错** (OOM command not allowed)。读请求依然可以正常处理。

  - **场景**：Redis 用作**纯数据库**（不能丢数据），或者需要严格控制内存，满了必须人工介入扩容。

### LRU | 时间维度

- **`allkeys-lru`：最常用**

  - **行为**：在所有 Key 中，淘汰很久没被访问过的。

  - **场景**：**通用缓存场景**。比如缓存用户信息、新闻列表。因为一般来说，刚才被访问的数据，等会儿大概率还会被访问（局部性原理）。

- `volatile-lru`

  - **行为**：只在设了过期时间的 Key 里，淘汰很久没被访问的。
  - **场景**：Redis 里混杂着“永久配置数据”和“临时缓存数据”，希望优先保住永久的配置数据。

### LFU | 频率维度

- **`allkeys-lfu`：最常用**
  - **行为**：在所有 Key 中，淘汰访问频率最低的。
  - **场景**：**防止一次性扫描污染**。
    - *例子*：有一个冷门数据，平时没人看。突然有个爬虫全量扫描了一遍。
    - *LRU* 认为它“刚刚被访问过”，把它留下了，反而把真正的热点数据挤走了。
    - *LFU* 认为它“虽然刚才被摸了一下，但历史访问次数很低”，照样淘汰它。

- `volatile-lfu`
  - **行为**：只在设了过期时间的 Key 里，淘汰频率最低的。

| **特性**   | **LRU (最近最少使用)**                                       | **LFU (最不经常使用)**                                       |
| ---------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **关注点** | **时间** (最后一次访问是几点？)                              | **热度** (一共访问了几次？)                                  |
| **优点**   | 能够迅速适应访问模式的突然变化（新热点来了，老热点迅速下线）。 | 抗干扰能力强。不会因为一次偶然的遍历（全表扫描）就把热点数据挤出去。 |
| **缺点**   | **缓存污染**：一个很久没用的 Key，刚才偶然被查了一次，LRU 就会认为它很重要，让它在内存里赖很久。 | 对突发的新热点不够敏感（因为它需要积累访问次数）。Redis 有老化机制来缓解这个问题。 |

### Random

- `allkeys-random`
- `volatile-random`

### TTL

- `volatile-ttl`：希望让即将过期的数据提前清理，腾出内存空间。

## 事务

提供了一个将多个命令打包、一次性提交的机制。

- **工作流程 **| 命令队列

  - **`MULTI`**：标记事务的开始。
  - **命令序列**：发送的命令不会立即执行，而是被服务器**放入队列 (Queue)**。
  - **`EXEC`**：执行事务。Redis 会将队列中的所有命令按顺序**不间断地**执行。
  - **`DISCARD`**：如果在 `EXEC` 之前改变主意，可以取消事务，清空队列。

- **主要作用**

  - **减少网络开销 (RTT)**：将几十个命令打包成一个事务，客户端只需发送一次 `MULTI` 和一次 `EXEC`，减少了多次网络往返时间，提高了效率。
  - **保证隔离性（原子性）**：一旦 `EXEC` 被触发，事务中的所有命令将作为一个整体被顺序执行，**不会被其他客户端的命令插队**。这保证了事务内部操作的连续性。

  > [!NOTE]
  >
  > 此处是弱原子性，**不保证所有命令执行成功**，如果其中有一个失败，还会接着执行之后的命令。

### 乐观锁

**乐观锁**其实不是一种真正的“锁”（不像互斥锁 Mutex 那样会阻塞线程），而是一种**并发控制策略**。

- **特点**

  - 全程不加锁；读的时候没有限制读，写的时候严格检查。
  - **重试开销大。**在并发写冲突剧烈时，大量请求会失败并不断重试，导致 CPU 飙升。

- **实现方式**

  - **版本号机制**

    1. **Read**：查询数据时，把 `version` 一起读出来。

       - `SELECT id, stock, version FROM product WHERE id=1;` (假设读出来 version=5)

    2. **Calculate**：在内存中做计算（比如库存 -1）。

    3. **Check & Update**：更新时，把刚才读出来的 `version=5` 作为 `WHERE` 条件，同时让版本号 +1。

       ```mysql
       UPDATE product 
       SET stock = stock - 1, version = version + 1 
       WHERE id = 1 AND version = 5;
       ```

    4. **Result**：

       - 如果数据库返回 **Affected Rows = 1**：说明期间没人改过，更新成功。
       - 如果数据库返回 **Affected Rows = 0**：说明 `version` 已经不是 5 了（被改成 6 了），更新失败。

  - **CAS 机制 (Compare And Swap)**

    不依赖额外的 version 字段，而是直接对比**值本身**。以Redis地`WATCH`为例：

    - `WATCH stock` (假设 stock 现在是 100)
    - `MULTI` ... `DECR stock` ... `EXEC`
    - **最终写入前Redis 检查**：`stock` 还是 100 吗？是就执行，不是就报错。

- **使用场景** | **读多写少**

  - 用户修改个人资料；
  - 文档编辑；
  - **不适合场景：**强一致性要求，如银行资金操作，购物秒杀活动

- **对比悲观锁**

  - 乐观锁对“读”完全开放，只在提交时通过版本号检测冲突，适合**高并发读**场景；
  - 悲观锁遵循“先锁后用”策略，利用数据库锁机制实现数据的**独占访问**，虽然牺牲了并发度，但保证了**强一致性和高度原子性**，适合**写竞争激烈**的场景。

# 高可用与集群部署

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-主从+哨兵.drawio.svg" alt="Redis-主从+哨兵.drawio" style="zoom:120%;" />

## 主从复制

- **读写分离：** Master 负责写，Replica 负责读（提高读并发）。

- **同步机制：**

  - **全量同步 (RDB)：** 刚连接或重连时，Master 生成 RDB 快照发给 Slave。

  - **增量同步 (Replication Buffer)：** 稳定状态下，Master 将写命令流式传给 Slave。

- **无盘复制：** 在磁盘 I/O 慢但网络快的情况下，直接通过网络发送 RDB 数据，不落地磁盘。

> 测试

- **Master节点**

  ```bash
  127.0.0.1:6379> info replication
  # Replication
  role:master
  connected_slaves:2
  slave0:ip=172.21.0.2,port=6379,state=online,offset=98,lag=0
  slave1:ip=172.21.0.4,port=6379,state=online,offset=98,lag=0
  ```

  - **写入数据**

    ```bash
    127.0.0.1:6379> set system_status "running"
    OK
    ```

- **Slave节点**

  ```bash
  127.0.0.1:6379> info replication
  # Replication
  role:slave
  master_host:redis-master
  ```

  - **操作数据** | 只有“读”权限，没有“写”权限

    ```bash
    127.0.0.1:6379> get system_status
    "running"
    127.0.0.1:6379> set system_status "stopped"
    (error) READONLY You can't write against a read only replica.
    ```

## 哨兵模式

主从模式解决了数据备份，但无法自动故障恢复。哨兵解决了**自动化运维**的问题。

- **监控：** 哨兵不断检查 Master 和 Slave 是否正常。
- **故障转移：** Master 挂了，哨兵投票选举一个新的 Master。
- **通知：** 将新 Master 的地址通知给客户端（这对于以后写 Go 后端连接 Redis 很重要，连接的是哨兵地址，而非直连Master）。
- **选举机制：** 涉及 Raft 算法的简化版，需要半数以上哨兵同意。

### `sentinel.conf`

注意此处必**须显式声明**允许redis主节点host的DNS解析，否则只认IP地址而不认识容器名称。

```cobol
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
# 哨兵端口
port 26379

# 工作目录
dir /tmp

# 核心监控指令：监控名为 mymaster 的主节点
# 格式：sentinel monitor <主节点别名> <主节点host> <端口> <票数>
# "redis-master" 是在 docker-compose 里定义的服务名
# "2" 代表至少需要 2 个哨兵同意，才能判定 Master 挂了
sentinel monitor mymaster redis-master 6379 2

# 判定服务器断线的时间（毫秒）
# 默认是 30秒，为了测试方便改为5秒
sentinel down-after-milliseconds mymaster 5000

# 故障转移超时时间
sentinel failover-timeout mymaster 60000

# 故障转移后，同时同步新 Master 的 Slave 数量
sentinel parallel-syncs mymaster 1
```

### `docker-compose.yml`

```yaml
  sentinel1:
    image: redis:latest
    container_name: sentinel1
    ports:
      - "26379:26379"
    command: >
      sh -c "cp /etc/redis/sentinel.conf /tmp/sentinel.conf &&
            sleep 5 &&
            redis-sentinel /tmp/sentinel.conf"
    volumes:
      - ./sentinel.conf:/etc/redis/sentinel.conf
    networks:
      - redis-test
    depends_on:
      redis-master:
        condition: service_healthy

...
```

- 挂载本地`.conf`文件到容器目录下；
- 从容器目录下拷贝副本，通过副本启动哨兵；
- **目的：**防止 3 个哨兵容器同时修改宿主机上的同一个 `sentinel.conf` 文件导致冲突（Windows 下文件锁问题）。

### 测试

1. 进入哨兵中查看主从节点状态是否准确获取；

   ```bash
   docker exec -it sentinel1 redis-cli -p 26379
   ```

   此处需要**显式**指出哨兵服务监听的端口，因为`redis-cli`默认监听`localhost:6379`，而哨兵节点下只有Senteinel进程在运行。

   查看Master和Slave的信息：

   ```bash
   127.0.0.1:26379> sentinel master mymaster
    1) "name"
    2) "mymaster"
    3) "ip"
    4) "redis-master"
    5) "port"
    6) "6379"
    ...
   ```

   ```bash
   27.0.0.1:26379> sentinel slaves mymaster
   1)  1) "name"
       2) "172.21.0.2:6379"
       3) "ip"
       4) "172.21.0.2"
       5) "port"
       6) "6379"
       ...
   2)  1) "name"
       2) "172.21.0.3:6379"
       3) "ip"
       4) "172.21.0.3"
       5) "port"
       6) "6379"
       ...
   ```

2. 手动“暂停”主节点；

   ```bash
   docker pause redis-master
   ```

   此处不能直接`stop`或删除容器，否则DNS记录也会消失。

3. 观察任意哨兵日志；

   ```bash
   docker logs -f sentinel1
   ```

   ```bash
   12:X 05 Dec 2025 09:02:36.842 # +vote-for-leader a1e3b8582622d0167e742a996bfe4e0f2da1bd46 1
   12:X 05 Dec 2025 09:02:37.867 # +odown master mymaster redis-master 6379 #quorum 3/2
   ...
   12:X 05 Dec 2025 09:02:37.924 # +config-update-from sentinel a1e3b8582622d0167e742a996bfe4e0f2da1bd46 172.21.0.6 26379 @ mymaster redis-master 6379
   12:X 05 Dec 2025 09:02:37.924 # +switch-master mymaster redis-master 6379 172.21.0.3 6379
   ```

   注意到：

   - `+vote-for-leader`(投票选择新的主节点)

   - `+odown master` (客观下线)

   - `+switch-master` (切换成功)

4. 查看“从节点”状态：已经升级为新的主节点

```bash
dantalion@Dantalion:~/redis$ docker exec -it redis-slave1 redis-cli
127.0.0.1:6379> info replication
# Replication
role:master
connected_slaves:1
```

# 后端系统设计与Go语言集成

## 缓存设计模式

因为某种原因，大量请求绕过了缓存（Redis），直接打到了数据库（MySQL），导致数据库负载激增甚至崩溃。

**Redis+MySQL经典的配合流程：**

1. 用户请求数据。
2. 后端先去 **Redis** 查。
   - 如果有（Hit）：直接返回，**完全不打扰 MySQL**。
   - 如果没有（Miss）：再去 **MySQL** 查，查到了返回给用户，并顺手把数据**写回 Redis**，方便下一次查询。

| **维度**     | **MySQL (关系型数据库)** | **Redis (NoSQL/缓存)**   | **关系总结**                                      |
| ------------ | ------------------------ | ------------------------ | ------------------------------------------------- |
| **存储介质** | 磁盘 (Disk/SSD)          | 内存 (RAM)               | **互补：** 一个存得久，一个存得快                 |
| **查询方式** | SQL (复杂的表关联)       | Key-Value (简单的键值对) | **互补：** 一个处理复杂逻辑，一个处理简单高频查询 |
| **数据量**   | TB / PB 级别             | GB 级别                  | **互补：** 一个存全量数据，一个存热点数据         |

### 缓存穿透

- **定义：** 查询一个**根本不存在的数据**。因为数据不存在，缓存中肯定没有，数据库中也没有。导致每次请求都要去查数据库，最后返回空。这就相当于缓存成了“透明”的，请求直接“穿透”到了数据库。

- **实际表现：**
  - **场景：** 恶意攻击者使用脚本不断请求不存在的 ID（例如 `id = -1` 或 UUID）。
  - **后果：** 数据库虽然查不到数据，但大量的 IO 查询操作会瞬间耗尽数据库连接资源。
  
- **应对方法：**
  1. **缓存空对象：**
  
     <img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-缓存穿透+空对象.drawio.svg" alt="Redis-缓存穿透+空对象.drawio" style="zoom:120%;" />
  
     - **原理：** 当数据库查不到数据时，不直接返回，而是将 key 的值设为 `null` 或特定标识符写回 Redis，并设置一个较短的过期时间（如 30秒）。
     - **优点：** 实现简单。
     - **缺点：** 会缓存很多垃圾 key，浪费内存；且存在数据不一致的时间窗口。
  
  2. **布隆过滤器：**
  
     <img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-缓存穿透+布隆过滤器.drawio.svg" alt="Redis-缓存穿透+布隆过滤器.drawio" style="zoom:120%;" />
  
     - **原理：** 在访问缓存之前，先经过一个布隆过滤器。它能以极小的空间快速判断“这个 ID 肯定不存在”或“可能存在”。如果判断不存在，直接拦截，不查缓存也不查库。
     - **优点：** 内存占用极少，拦截效率极高。
     - **缺点：** 代码逻辑较复杂；存在极小概率的误判（它说存在可能不存在，但它说不存在就一定不存在）。
  
  3. **接口层校验：**
     - 做好参数校验，对于明显不合法的 ID（如负数、格式错误的 ID）直接在 API 层拦截。

### 缓存击穿

- **定义：** 一个**非常热点**的 Key（Hot Key），在不停地扛着大并发，大并发集中对这一个点进行访问。当这个 Key 在失效的瞬间，持续的大并发就穿破缓存，直接请求数据库，就像在一个完好的桶上凿了一个洞。

- **实际表现：**

  - **场景：** 微博热搜、秒杀活动的商品详情页。假设该数据缓存过期时间是 12:00:00，在 12:00:01 秒有 1 万个请求同时进来。

  - **后果：** 数据库瞬间压力过大，但通常只是这一个数据相关的表压力大。

  - **应对方法：**

    1. **互斥锁：**

       - **原理：** 当缓存失效时，不立即去 load db，而是先使用 Redis 的 `SETNX` 去抢一个锁。抢到锁的线程去查询数据库并更新缓存，其他线程等待或在一定时间内重新读取缓存，缓存命中后直接返回数据，不再查库。
       - **优点：** 强一致性，保证只有一个请求打到数据库。
       - **缺点：** 性能有所下降，吞吐量降低。

       > 使用Go Singleflight优化互斥锁，实现**合并读**

       <img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-Singleflight.drawio.svg" alt="Redis-Singleflight.drawio" style="zoom:120%;" />

       **优点：**第一个请求查到数据后直接唤醒所有等待中的请求并返回数据，消去剩余请求的重试+等待时间。
    
       1. 查询全局Map：`map[string]*Call`
       2. 发现Map里没有Call $\rightarrow$ 创建一个Call对象；
       3. 通过`call.wg.Add(1)`加锁；
       4. 存入全局Map中；然后去数据库查询热点Key的值；
       5. 后续查询查到有Call存在，进入`call.wg.Wait()`状态；
       6. 查到后存入Call中，`call.wg.Done()`唤醒等待的所有人；
       7. 从Call中取出数据然后返回，并且清理Map。

    2. **逻辑过期：**
    
       - **原理：** 在 Redis 存储数据时，不设置 TTL（物理过期时间），而是在 value 内部包含一个“过期时间”字段。查询时，如果发现逻辑时间已过期，直接返回旧数据，同时开启一个**异步线程**去构建新数据更新缓存。
       - **优点：** 高可用，性能极高。
       - **缺点：** 会在异步更新完成前返回旧数据（牺牲了一致性）。

    > Singleflight + 逻辑过期
    
    ```go
    import (
        "context"
        "encoding/json"
        "errors"
        "time"
        "golang.org/x/sync/singleflight"
    )
    
    var g singleflight.Group
    
    // 定义缓存结构
    type Data struct {
        Val      string `json:"val"`
        ExpireAt int64  `json:"expire_at"` // 逻辑过期时间戳 (Soft TTL)
    }
    
    func GetData(ctx context.Context, key string) (string, error) {
        // 第一层：Redis 查询
        cacheVal, err := redisClient.Get(ctx, key).Result()
    
        // CASE A: 物理缓存彻底没数据 (缓存穿透/冷启动/物理过期)
        if err == redis.Nil {
            // 使用DoChan控制“应用层超时”
            ch := g.DoChan(key, func() (interface{}, error) {
                // 查库
                return fetchFromDBAndSaveToRedis(key) 
            })
    
            // Singleflight + 超时控制 + Forget
            select {
            case result := <-ch:
                // 1. 正常拿到结果
                if result.Err != nil {
                    return "", result.Err
                }
                return result.Val.(string), nil
    
            case <-time.After(2 * time.Second): // 设定业务容忍的最大等待时间
                // 2. DB超时
                g.Forget(key) 
                
                return "", errors.New("timeout fetching data")
            }
        }
    
        // 第二层：逻辑过期检查
        var data Data
        _ = json.Unmarshal([]byte(cacheVal), &data)
    
        // 检查逻辑时间戳是否过期
        if time.Now().Unix() > data.ExpireAt {
            // CASE B: 数据存在，逻辑过期 (Stale Data)
            
            // 开启一个 Goroutine 去后台更新
            go func() {
                g.Do("update:"+key, func() (interface{}, error) {
                    // 1. 创建独立的 Context，与主请求解绑
                    bgCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
                    defer cancel()
    
                    // 2. 查库
                    newVal := dbQuery(bgCtx, key)
    
                    // 3. 构造新数据，重置逻辑过期时间
                    newData := Data{
                        Val:      newVal,
                        ExpireAt: time.Now().Add(10 * time.Minute).Unix(),
                    }
                    
                    // 4. 写回 Redis
                    saveToRedis(bgCtx, key, newData)
                    return nil, nil
                })
            }()
        }
    
        // 第三层：返回结果
        return data.Val, nil
    }
    ```
    
    - **物理穿透防御**
      - **机制：** `Singleflight` (`DoChan`) + `Select Timeout` + `Forget`
      - **逻辑：**
        - **流量合并：** 1000 个并发请求只放行 1 个去查库。
        - **超时熔断：** 使用 `DoChan` 配合 `time.After`，如果 DB 查询超过 2 秒，立即给前端返回超时错误，而不是死等。
        - **故障隔离 (`Forget`)：** 一旦发生超时，立即调用 `Forget` 清理 Singleflight 的 Map。防止因 DB 持续卡顿，导致后续新请求误入“僵尸任务”的等待队列。
    - **逻辑过期防御**
      - **机制：** `Redis Value Timestamp` + `Async Goroutine`
      - **逻辑：**
        - **零等待：** 发现数据逻辑过期（ExpireAt < Now），不阻塞当前请求，**直接返回旧数据**。
        - **异步续期：** 启动后台 Goroutine 去查库更新。
        - **更新去重：** 后台更新也使用 `Singleflight`（Key 增加 `update:` 前缀），确保对同一个 Key，后台只有一个线程在跑 SQL，避免浪费数据库算力。

### 缓存雪崩

- **定义：**指在某一个时间段，缓存**集中过期失效**，或者 **Redis 节点宕机**。导致原本被缓存挡住的海量请求，瞬间全部涌向数据库。
- **实际表现：**
  - **场景：** 系统重启后加载缓存，设置了**相同的过期时间**（例如都是 1 小时）。1 小时后，所有缓存**同时失效**。
  - **后果：** 数据库会收到来自所有业务的压力，大概率直接宕机，甚至导致连锁反应（DB 挂了 -> 重启 -> 流量进来又挂），整个系统瘫痪。
- **应对方法：**
  1. **设置随机过期时间：**
     - **原理：** 在原有的过期时间基础上，增加一个随机值（例如 1-5 分钟）。这样原本同时过期的 Key 就会分散开来。
  2. **构建高可用缓存集群：**
     - **原理：** 使用 Redis Sentinel 或 Redis Cluster，防止单点故障导致全盘崩溃。
  3. **服务降级与限流：**
     - **原理：** 当流量洪峰到达时，启用限流组件（如 Sentinel、Hystrix），对非核心业务直接返回默认值或错误提示，保住核心数据库。
  4. **多级缓存：**
     - **原理：** 增加本地缓存（如 Guava Cache、Caffeine）作为一级缓存，Redis 作为二级缓存。Redis 挂了，本地还能撑一阵。

| **特性**     | **缓存穿透 (Penetration)** | **缓存击穿 (Breakdown)** | **缓存雪崩 (Avalanche)**           |
| ------------ | -------------------------- | ------------------------ | ---------------------------------- |
| **根本原因** | 数据根本不存在             | **单一热点 Key** 过期    | **大量 Key** 同时过期 / Redis 宕机 |
| **发生范围** | 随机或恶意的 Key           | 特定点的 Key             | 整个缓存层                         |
| **核心解法** | 布隆过滤器、缓存空值       | 互斥锁、逻辑过期         | 随机 TTL、集群高可用、限流降级     |

## 分布式锁

**分布式锁**是控制分布式系统之间同步访问共享资源的一种方式，核心价值在于**跨进程/跨主机的共享资源互斥访问**。

- **使用场景**
  - **资源强一致性控制** | 防止超卖
    - **场景：** 类似于 SKU 库存扣减、资金账户扣款、优惠券核销。
    - **痛点：** 避免并发条件下的“超卖”或“数据脏写”。
    - **特性：** 对锁的可靠性要求极高（CP 倾向）。
  - **分布式协同与领主选举** | 定时任务防重复执行
    - **场景：** 分布式定时任务（如 CronJob）、ETL 数据清洗任务。
    - **痛点：** 确保多实例部署的服务中，同一时刻只有一个节点（Leader）执行特定任务，避免重复执行造成资源浪费或数据污染。
    - **特性：** 锁丢失通常可容忍（任务下个周期再跑即可），强调防重。
  - **高并发幂等性保障** | 用户重复提交
    - **场景：** 交易支付接口、表单提交。
    - **痛点：** 防止网络抖动导致的重复请求穿透应用层防重逻辑，直接冲击数据库。
    - **特性：** 锁的持有时间通常很短（请求处理周期）。

- **实现流程**

  1. **加锁**

     **`SET key token NX PX 30000`**

     - **NX：** Only set if Not Exists（互斥）。
     - **PX：** 设置毫秒级过期时间（兜底，防死锁）。
     - **Token：** 必须是**全局唯一标识**（如 UUID + ThreadID），用于标识锁的归属权，防止误删他人锁。

  2. **守护与续期**

     解决“业务执行时间 > 锁 TTL”导致锁提前失效的问题。

     - **机制：** 客户端获取锁成功后，启动一个后台守护线程（Watchdog）。

     - **逻辑：** 每隔 TTL/3 的时间检查一次，如果业务仍在运行且持有锁，则重置 TTL。

  3. **解锁**

     必须保证“验证身份”与“删除锁”的原子性。

     - **机制：** 使用 **Lua 脚本**。

     ```lua
     if redis.call("get", KEYS[1]) == ARGV[1] then
         return redis.call("del", KEYS[1])
     else
         return 0
     end
     ```

     - 只有 Redis 中的 Value 等于客户端持有的 Token 时，才执行 DEL。

### redsync库

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-redsync.drawio.svg" alt="Redis-redsync.drawio" style="zoom:100%;" />

```go
package main

import (
	"time"
	"github.com/go-redsync/redsync/v4"
	"github.com/go-redsync/redsync/v4/redis/goredis/v9"
	goredislib "github.com/redis/go-redis/v9"
)

func main() {
	// 1. 创建 Redis 客户端连接
	client := goredislib.NewClient(&goredislib.Options{Addr: "localhost:6379"})
	pool := goredis.NewPool(client) // 适配器模式，把 go-redis 包装给 redsync 用

	// 2. 创建 Redsync 实例，管理连接池 (如果是 Redlock，这里传入多个 pool)
	rs := redsync.New(pool)

	// 3. 定义锁对象 (并未真正请求 Redis)
	mutexName := "resource:product:1001"
	mutex := rs.NewMutex(mutexName,
		redsync.WithExpiry(10*time.Second), // 物理 TTL：10秒
		redsync.WithTries(3),               // 重试次数：抢不到再试3次
		redsync.WithRetryDelay(100*time.Millisecond), // 重试间隔
	)

	// 4. 原子操作加锁 (SETNX + PX + Token)
	if err := mutex.Lock(); err != nil {
		panic("抢锁失败，系统繁忙") // 实际业务中应降级处理
	}

	// 5. 启动后台协程自动续期 (解决业务耗时 > TTL 问题)
	stopWatchdog := make(chan bool)
	go func() {
		// 间隔设置为 TTL 的 1/3 比较合适
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stopWatchdog:
				return // 业务结束，停止续期
			case <-ticker.C:
				// 执行 Lua 脚本原子续期
				if ok, _ := mutex.Extend(); !ok {
					return // 续期失败(可能Redis挂了)，退出防止死循环
				}
			}
		}
	}()

	// 6. 模拟业务处理 15秒 (超过了初始的 10秒 TTL)
	time.Sleep(15 * time.Second) 

	// 7. 停止检查TTL
	close(stopWatchdog)

	// 8. 原子操作解锁 (Lua Check-And-Delete)
	if ok, err := mutex.Unlock(); !ok || err != nil {
		panic("解锁异常") 
	}
}
```

**封装处理逻辑总结**

- **`rs.NewMutex(...)` (配置阶段)**
  - **Token 生成**：自动在内存生成一个 `Base64` 随机字符串作为 value，作为**身份唯一标识**。
  - **参数预设**：将 TTL、重试策略绑定到结构体中，尚未发生网络交互。
- **`mutex.Lock()` (竞争阶段)**
  - **原子抢占**：并发向所有 Redis 节点发送 `SET key token NX PX 10000`。
  - **过半机制**：(Redlock模式) 统计成功节点数，必须 `≥ N/2 + 1` 才算成功。
  - **超时回滚**：如果网络超时或未凑够节点，自动发起 `Unlock` 清理脏数据。
- **`mutex.Extend()` (守护阶段)**
  - **原子续命**：发送 Lua 脚本。
  - **逻辑**：`if redis.get(key) == my_token then return redis.expire(key, 10s)`。
  - **作用**：防止业务还在跑，锁却过期被别人抢走。

- **`mutex.Unlock()` (释放阶段)**
  - **原子校验**：发送 Lua 脚本。
    - **逻辑**：`if redis.get(key) == my_token then return redis.del(key)`。
    - **安全保障**：绝对保证**只删自己的锁**，即使当前锁已经过期（被别人抢了），这行代码也不会误删别人的新锁。

## 小结 | 高并发读写场景

### 高并发读 | 防御体系

1. **缓存异常与解法**

   | **问题**     | **现象**                                 | **核心解法**                                                 |
   | ------------ | ---------------------------------------- | ------------------------------------------------------------ |
   | **缓存穿透** | 查**不存在**的数据，请求直打 DB。        | **布隆过滤器 (Bloom Filter)**、缓存空值 (Null)。             |
   | **缓存击穿** | **热点 Key** 过期，大量并发请求直打 DB。 | **互斥锁** (强一致)、**逻辑过期** (高可用)、**Singleflight**。 |
   | **缓存雪崩** | **大量 Key** 同时过期或 Redis 宕机。     | **随机 TTL**、Redis 集群、多级缓存、限流降级 (Sentinel)。    |

2. **Singleflight核心逻辑**

   - **定位：** 进程内（Goroutine 级别）的**读请求合并**。

   - **原理：** 1000 个请求查同一个 Key，利用 `WaitGroup` 阻塞 999 个，只放 1 个去查库，结果共享。

   - **适用场景：** 热点数据读取（如微博热搜）。

   - **架构陷阱：** 如果 DB 慢查询，会导致大量 Goroutine 阻塞。

   - **优化：** 配合 `DoChan` + `Select Timeout` + `Forget`，防止死等。

3. **热点Key的架构设计思想**

   不要让用户等待 DB 查询，追求**最终一致性**。

   - **方案：** **逻辑过期 + 异步更新**。
   - **流程：** Redis Key 永不过期（物理上） -> 发现逻辑时间过期 -> 返回旧数据（秒级响应） -> 后台起协程抢锁异步更新缓存

### 高并发写 | 严格互斥

1. **分布式锁的底层实现**

   任何成熟的客户端库（如 `redsync`, `Redisson`）底层必须包含的逻辑：

   1. **互斥性:** `SETNX` (Set if Not Exists)。这是锁的基础。
   2. **身份标记:** `Value = Token(UUID)`。防止误删别人的锁。
   3. **容错兜底 :** `PX 10000` (TTL)。确保锁会自己过期，防止客户端宕机导致死锁。
   4. **自动续期:** 后台线程每隔一段时间重置 TTL。防止业务执行时间 > 锁过期时间，导致锁提前失效，数据被别人加锁。
   5. **原子解锁:** **Lua 脚本**。Check Token 和 Del Key 必须在一次原子操作中完成。

2. **Redlock vs. 标准 Redis 锁**

   - **标准 Redis 锁 (95% 场景):** 复用现有的 Redis 集群（单写）。
   - *风险:* 主从切换的瞬间可能会丢锁（AP 模型）。
   - *适用:* 非资金核心业务。

   - **Redlock (5% 场景):** 部署 5 个独立的 Master，过半写入才算成功。
     - *成本:* 极高。
     - *替代:* 如果真要强一致性，建议直接用 **ZooKeeper** 或 **Etcd** (CP 模型)。

## 分布式限流

防止瞬间大流量（DDoS 或 爬虫）把服务打挂。

### 固定窗口计数器

- **定义：** 单位时间（如 1秒）内，限制 N 个请求。

- **Redis 实现：**

  - Key = `limit:api:2023-12-06 12:00:01`

  - `INCR key` -> 如果结果 > N 则拒绝。

  - `EXPIRE key 1`。

- **致命缺陷：临界突发**
  - 假设限制 100 QPS。
    - 第 0.9 秒来了 100 个请求（通过）。
    - 第 1.1 秒又来了 100 个请求（通过）。
  - **结果：** 在 0.9s ~ 1.1s 这 **0.2秒** 内，系统承受了 **200** 个请求。这一瞬间的压力可能把数据库打挂。

### 滑动窗口

- **定义：** 为了解决临界问题，把窗口像胶卷一样平滑移动。

- **Redis 实现：** 使用 **ZSET**。

  - Key = `limit:api`

  - Value = UUID, Score = 当前时间戳。

  - **逻辑：**
    1. `ZADD` 添加当前请求。
    2. `ZREMRANGEBYSCORE` 删除 `(当前时间 - 窗口大小)` 之前的旧数据。
    3. `ZCARD` 统计剩下的数量。如果 > N，则拒绝

- **致命缺陷：资源消耗大**
  - 它需要存储窗口内**所有**请求的记录。且 ZADD/REMRANGE 的时间复杂度较高，不适合高并发。

### 令牌桶

生产环境最常用的算法。在 Redis 分布式场景下，通常使用 **“惰性计算”** 的方式来实现。

- **定义：**一个存放令牌的桶。**系统以恒定的速度往桶里扔令牌**。请求来了，必须拿到一个令牌才能通过。如果桶满了，令牌就扔不进去了。
- **核心特性：** **允许突发**
  - 如果系统空闲了一段时间，桶里积攒了很多令牌（直到达到容量上限）。
  - 此时如果突然涌入大量请求，只要桶里有令牌，就能瞬间全部处理，不用排队。

- **应用场景**：绝大多数互联网 API 限流
- **Redis实现：**通过Lua脚本
  - **核心思想：** **在请求来的一瞬间，算出“这段时间该生成多少令牌”**。
  - **存储结构：** Hash `{ "last_refill_time": 上次加令牌时间, "tokens": 当前剩余令牌数 }`
  - **参数：** `capacity` (桶上限), `rate` (每秒生成几个)。
  - **逻辑流：**
    1. `now` = 当前时间。
    2. `time_passed` = `now - last_refill_time`。
    3. **计算生成的令牌：** `new_tokens = time_passed * rate`。
    4. **更新当前令牌数：** `current_tokens = min(capacity, tokens + new_tokens)`。
    5. **尝试消费：** 如果 `current_tokens >= 1`，则允许通过，`current_tokens--`，更新 `last_refill_time = now`。
    6. 否则，拒绝。
- **使用Lua脚本：**确保更新与消费令牌的过程是原子性的，避免出现并发竞态，导致限流失效。

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-令牌桶.drawio.svg" alt="Redis-令牌桶.drawio" style="zoom:120%;" />

> 示例

**`rate_limit.lua`**

```lua
-- KEYS[1]: 限流的 Key，例如 "rate:limit:user:1001"
-- ARGV[1]: 桶的容量 (capacity)，例如 10
-- ARGV[2]: 令牌生成速率 (rate/秒)，例如 1
-- ARGV[3]: 当前请求消耗的令牌数，通常是 1
-- ARGV[4]: 当前时间戳 (秒或毫秒)

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])
local tokens_needed = tonumber(ARGV[3])
local now = tonumber(ARGV[4])

-- 1. 获取当前存储的值
-- saved_tokens: 上次剩余的令牌数
-- last_refill: 上次填充的时间
local info = redis.call("HMGET", key, "tokens", "last_refill")
local saved_tokens = tonumber(info[1])
local last_refill = tonumber(info[2])

-- 2. 初始化 (如果是第一次访问)
if not saved_tokens then
    saved_tokens = capacity
    last_refill = now
end

-- 3. 计算这段时间新生成的令牌 (Lazy Calculation)
local delta = math.max(0, now - last_refill)
local generated = delta * rate

-- 4. 计算当前总令牌数 (不能超过容量)
local current_tokens = math.min(capacity, saved_tokens + generated)

-- 5. 判断是否足够
local allowed = 0
if current_tokens >= tokens_needed then
    allowed = 1
    current_tokens = current_tokens - tokens_needed
    redis.call("HMSET", key, "tokens", current_tokens, "last_refill", now)
    -- 设置个过期时间，防止死数据，例如 capacity / rate * 2
    redis.call("EXPIRE", key, 60) 
end

return allowed
```

**Go调用**

```go
func AllowRequest(userId string) bool {
    // 限制规则：容量10，每秒1个
    capacity := 10
    rate := 1
    now := time.Now().Unix() // 使用秒级时间戳

    // 执行 Lua 脚本
    result, err := rdb.Eval(ctx, luaScript, 
        []string{"rate:limit:" + userId}, // KEYS
        capacity, rate, 1, now           // ARGV
    ).Result()

    return result.(int) == 1
}
```

## 消息队列

消息队列是分布式系统中用于**“异步通信”**的中间件。

- **Producer ：** 发信人。也就是上游服务（比如 `Frontend`），它只管把数据丢进传送带。
- **Broker：** 传送带。负责暂存数据，保证不丢，并按照顺序排好。
- **Consumer：** 收信人。也就是下游服务（比如 `CheckoutService`），它根据自己的处理能力，慢慢地从传送带取出数据，然后解析、处理、回应。
- **核心作用：**
  - **解耦**
    - 上游发出请求时不关心下游的具体情况。
  - **削峰**
    - 请求到达下游前在Broker堆积，而不是直接打到下游。

### 布隆过滤器

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Redis-布隆过滤器.drawio.svg" alt="Redis-布隆过滤器.drawio" style="zoom:120%;" />

**定位：**不是最终的数据存储源，而是用于保护后端存储（DB/Cache）免受无效请求轰炸的**防御组件**。

1. **核心定义**

   一种**极度节省内存**的概率型数据结构，用于判断**“一个元素是否在一个集合中”**。

   - **本质：** 利用位数组和多个哈希函数来压缩数据存储。
   - **特点：**
     - 如果它说**“不存在”**，那一定**不存在**（100% 准确）。
     - 如果它说**“存在”**，那**可能存在，也可能不存在**（存在误判率）。

2. **数据结构构成**

   1. **位数组：**
      - 长度为 $m$ 的二进制向量。
      - 初始化状态下，所有位均为 `0`。
      - 内存占用极低（例如存 10 亿数据仅需几百 MB）。
   2. **哈希函数组：**
      - $k$ 个相互独立、分布均匀的哈希函数。
      - 输入：任意数据（如 String, Int）。
      - 输出：范围在 $[0, m-1]$​ 之间的整数索引。

3. **工作流程**

   1. **写入流程**

      - **哈希计算：** 将 Key 分别通过 $k$ 个哈希函数进行计算，得到 $k$ 个哈希值。
      - **取模映射：** 将这 $k$ 个哈希值对位数组长度 $m$ 进行取模运算，得到 $k$ 个数组下标位置。
      - **落位标记：** 将位数组中这 $k$ 个位置的二进制位全部置为 `1`。
        - *注：如果某位置已经是 1，则保持为 1（覆盖）。*

   2. **查询流程**

      - **哈希计算：** 同样将 Key 通过这 $k$ 个哈希函数计算，并取模得到 $k$ 个下标位置。
      - **状态检查：** 检查位数组中这 $k$ 个位置的二进制值。
      - **判定逻辑：**
        - **情况 A（不存在）：** 只要有**任意一个**位置的值为 `0`，说明该 Key 一定未被存储过。
          - *结论：直接拦截 (Block)。*
        - **情况 B（可能存在）：** 如果**所有 $k$ 个**位置的值都为 `1`，说明该 Key 可能存在。
          - *结论：放行 (Pass) -> 进入下一层存储（Redis/DB）进行二次确认。*

   3. **删除流程**

      - **标准布隆过滤器不支持删除操作**。

      - **原因：** 某个位为 `1` 可能是由多个不同的 Key 共同映射导致的（哈希碰撞）。如果将某一位重置为 `0`，可能会影响其他 Key 的正确判断（导致本来存在的 Key 被误判为不存在）。

        *解决方案：* 数据过期也直接通过，让请求打到数据库，或定期重建整个过滤器。

4. **关键指标与权衡**

   布隆过滤器的设计本质是**空间** 与 **误判率** 之间的权衡。
   
   - **位数组长度 ($m$)**：
     - $m$ 越大，空间占用越大，但位被填满的速度越慢，冲突概率越低，误判率越低。
   - **哈希函数个数 ($k$)**：
     - $k$ 太少：映射位置少，容易发生不同 Key 映射到完全相同位置的冲突。
     - $k$ 太多：存一个 Key 要涂黑很多位，位数组很快被填满，误判率反而上升，且计算耗时增加。
   - **最佳实践公式**：
     - 若预期元素数量为 $n$，期望误判率为 $p$，则：
       - 最佳位数组大小 $m \approx - \frac{n \ln p}{(\ln 2)^2}$
       - 最佳哈希函数个数 $k \approx \frac{m}{n} \ln 2$
