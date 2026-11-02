# Go 语言

> 定位：Go 后端高频面试题，按「问题 → 准确答案」组织。
> 标记：`[必会]` 必须脱口而出；`[高频]` 能说清结论和支撑点；`[加分]` 被追问时能答。

## [必会] 1. slice 和 array 有什么区别？slice 底层是什么？

- **结论**：array 是定长值类型，长度属于类型；slice 是 `{ptr, len, cap}` 的底层数组视图，赋值只拷贝切片头。

- **关键点**
  1. `[3]int` 和 `[4]int` 是不同类型；array 赋值/传参整体拷贝。
  2. slice header：`Data` 指针、`Len` 长度、`Cap` 容量；多个 slice 可共享同一底层数组。
  3. `append` 在 cap 足够时原地写；超过 cap 时分配新数组、拷贝旧数据，之后与原数组脱钩。
  4. 扩容：Go 1.18+，cap < 256 翻倍；更大时按约 1.25 倍增长，再按内存规格对齐。

- **对比**

  | 维度 | array | slice |
  |---|---|---|
  | 长度 | 编译期固定，属于类型 | 动态，可 append |
  | 赋值 / 传参 | 整体拷贝 | 只拷贝 header |
  | 底层数据 | 自身即数据 | 指向底层数组 |
  | 扩容 | 不支持 | 超过 cap 时重新分配 |

- **常见追问**
  - **slice 传参修改元素会影响原数组吗？** 会，共享底层数组；但 append 触发扩容后，新 slice 与原数组脱钩。
  - **Go 是值传递还是引用传递？** 只有值传递；slice/map/channel 传递的是描述符或指针的拷贝，所以能修改底层数据。
  - **make 和 new 的区别？** `new(T)` 返回 `*T` 零值；`make` 只用于 slice/map/channel，返回初始化后的值。
  - **`s[1:3]` 的 len 和 cap？** len=2，cap=`cap(s)-1`。

## [必会] 2. map 底层结构？扩容机制？

- **结论**：经典实现是 bucket 数组 + 溢出桶的哈希表，负载因子 6.5 触发增量扩容；Go 1.24 起 runtime 改为 Swiss table。

- **关键点**
  1. `hmap`：`count`、`B`（bucket 数 = 2^B）、`buckets`、`oldbuckets`、`nevacuate`。
  2. `bmap`：每个 bucket 存 8 个 key/value，`tophash[8]` 做快速比较，`overflow` 指向溢出桶。
  3. 定位：hash 低 B 位选 bucket，高 8 位与 tophash 比较。
  4. 扩容：`count > 6.5 * 2^B` 或溢出桶过多 → 2 倍扩容 / 等量扩容；渐进式迁移，每次写操作搬迁部分 bucket。
  5. key 必须可比较；slice/map/func 不能做 key。
  6. 不能取 map value 的地址，`m[k].field = x` 编译错误；需要修改时存指针或整体赋值。

- **常见追问**
  - **为什么负载因子是 6.5？** 空间利用率和查找效率的折中；太高溢出桶多，太低浪费内存。
  - **扩容期间怎么读写？** 先查 `oldbuckets`，再查 `buckets`；迁移中的 bucket 会被优先搬迁。
  - **Go 1.24 的 Swiss table 是什么？** runtime 层的新 map 实现，减少内存和查找开销；语言语义不变，面试通常仍问经典 bucket 模型（加分）。

## [必会] 3. map 为什么并发不安全？如何安全使用？遍历为什么随机？

- **结论**：map 没有内置锁，并发读写会触发 runtime fatal error；需加锁或使用 sync.Map；遍历顺序被故意随机化。

- **关键点**
  1. 并发写、并发读写 → `fatal error: concurrent map writes` / `concurrent map read and map write`；不是普通 panic，`recover` 捕获不了。
  2. 通用方案：`sync.RWMutex` + map；读多写少、key 集合稳定可用 `sync.Map`；超高并发可用分片 map。
  3. `sync.Map`：read map（atomic 读）+ dirty map + mutex；读命中 read 无锁，miss 时加锁查 dirty；写多时 dirty 提升为 read 有开销。
  4. 遍历随机：runtime 随机选择起始 bucket 和 cell，防止业务依赖顺序；需要有序遍历时收集 key 后排序。

- **常见追问**
  - **sync.Map 适合什么场景？** 读多写少、key 集合相对稳定，如缓存、配置；不适合频繁写。
  - **如何判断 key 是否存在？** `v, ok := m[k]`；不要用 `m[k] == nil`，因为 value 可能本来就是 nil。
  - **map 的 key 为什么必须可比较？** 需要哈希和相等比较；slice/map/func 不可比较。

## [必会] 4. interface 底层结构？nil interface 和 nil 指针有什么区别？

- **结论**：非空接口是 `iface{tab, data}`，空接口是 `eface{type, data}`；只有 type 和 data 都为 nil，接口才等于 nil。

- **关键点**
  1. `iface`：`tab *itab`（动态类型 + 方法表），`data` 指向动态值。
  2. `eface`：`_type` + `data`，用于 `interface{}` / `any`。
  3. `itab` 全局缓存；接口调用通过 itab 的方法表。
  4. nil interface：type 和 data 都 nil；`var err error = nil` → `err == nil`。
  5. 经典坑：`var p *MyError = nil; var err error = p` → `err != nil`，因为动态类型是 `*MyError`，data 为 nil。

- **对比**

  | 接口 | 底层 | 场景 |
  |---|---|---|
  | `iface` | tab + data | 有方法的接口 |
  | `eface` | type + data | `interface{}` / `any` |

- **常见追问**
  - **如何判断接口的动态类型？** type assertion、type switch、reflect。
  - **接口比较什么时候 panic？** 动态类型不可比较（slice/map/func）时。
  - **值接收者和指针接收者的方法集？** `T` 的方法集包含值接收者；`*T` 包含值和指针接收者。

## [必会] 5. GMP 调度模型是什么？

- **结论**：G 是 goroutine，M 是 OS 线程，P 是调度上下文；M 必须绑定 P 才能执行 G，P 的数量由 GOMAXPROCS 决定。

- **关键点**
  1. G：栈、状态、goid、绑定的 M。
  2. M：OS 线程，`g0` 调度栈，`curg` 当前 G。
  3. P：本地运行队列（256）、mcache、状态；数量默认为 CPU 核数。
  4. 调度：`go` 创建 G → 放入 P 本地队列 → M 绑定 P 执行；本地队列满则放全局队列；P 空闲时从全局队列取或 work stealing。
  5. 阻塞：channel/mutex → `gopark`，P 继续跑其他 G；系统调用 → P handoff 给其他 M。
  6. 抢占：sysmon 检测运行超过约 10ms 的 G，Go 1.14+ 通过信号异步抢占。

- **常见追问**
  - **GOMAXPROCS 默认值？** 默认 CPU 核数；容器环境 CPU 配额与宿主机核数不一致时，建议 automaxprocs 或显式设置。
  - **为什么 P 的本地队列是 256？** 降低全局队列锁竞争。
  - **work stealing 怎么偷？** 随机选 victim，偷走约一半 G。

## [必会] 6. goroutine 什么时候让出 P？

- **结论**：主动阻塞（channel/锁/IO）、系统调用 handoff、时间片耗尽/抢占时让出。

- **关键点**
  1. channel 阻塞、mutex 阻塞、`time.Sleep` → `gopark`，G 进等待队列，P 跑其他 G。
  2. 网络 IO → netpoller，G 挂起但不占 M；就绪后重新入队。
  3. 文件 IO、cgo 等系统调用 → `entersyscall`，P 与 M 解绑（handoff），M 阻塞，P 找其他 M。
  4. 函数调用栈检查 / 协作式抢占点；Go 1.14+ sysmon 异步抢占长时间运行的 G。
  5. 时间片约 10ms；G 回到本地队列尾部。

- **常见追问**
  - **G 阻塞在系统调用，P 会一直等吗？** 不会，handoff 给其他 M。
  - **为什么需要抢占？** 防止死循环 G 饿死其他 G。
  - **抢占是精确的吗？** 异步抢占基于信号，可能在安全点；栈扫描需要一致状态。

## [必会] 7. channel 底层结构？发送/接收流程？

- **结论**：`hchan` 包含环形缓冲区、`sendq` / `recvq` 等待队列和互斥锁；收发优先直接配对，其次缓冲区，最后阻塞。

- **关键点**
  1. `hchan`：`qcount`、`dataqsiz`、`buf`、`elemsize`、`closed`、`sendx`、`recvx`、`recvq`、`sendq`、`lock`。
  2. 无缓冲：`dataqsiz=0`，发送必须等接收者；有缓冲：环形队列。
  3. 发送：`recvq` 有等待者 → 直接拷贝给接收者；缓冲区有空位 → 入队；否则当前 G 包装成 `sudog` 入 `sendq`，`gopark`。
  4. 接收：`sendq` 有等待者 → 直接取；缓冲区有数据 → 出队；否则入 `recvq`，`gopark`。
  5. 唤醒：配对后唤醒对方；`close` 唤醒所有等待者。

- **常见追问**
  - **无缓冲 channel 为什么能同步？** 发送和接收直接配对，双方 rendezvous。
  - **channel 是值拷贝还是引用？** channel 本身是引用类型，拷贝的是 `hchan` 指针；发送的是元素值的拷贝。
  - **缓冲 channel 满/空时行为？** 满时发送阻塞，空时接收阻塞。

## [必会] 8. channel 关闭规则？select 原理？

- **结论**：由发送方关闭，只关一次；关闭后接收返回零值 + `ok=false`；select 随机选择一个就绪 case。

- **关键点**
  1. 关闭规则：

     | 操作 | 结果 |
     |---|---|
     | 向已关闭 channel 发送 | panic |
     | 重复关闭 | panic |
     | 关闭 nil channel | panic |
     | 向 nil channel 收发 | 永久阻塞 |
     | 读取已关闭 channel | 读完缓冲后返回零值，`ok=false` |

  2. select：求值所有 channel 表达式 → 随机打乱 case 顺序 → 有就绪则执行 → 否则执行 default → 没有 default 则阻塞。
  3. nil channel 的 case 永久禁用，可用来动态关闭分支。
  4. `close(ch)` 可作为广播信号，所有接收者同时被唤醒。

- **常见追问**
  - **如何优雅关闭多个 goroutine？** `close(done)` 广播，或 context 取消。
  - **如何判断 channel 已关闭？** `v, ok := <-ch`，`ok=false`。
  - **select 是公平的吗？** 随机选择，避免固定顺序导致饥饿。

## [必会] 9. Mutex 正常模式/饥饿模式？RWMutex 区别？

- **结论**：Mutex 正常模式自旋 + 排队，等待超过 1ms 进入饥饿模式，直接交给队首 waiter；RWMutex 是多读单写。

- **关键点**
  1. `state`：`locked`、`woken`、`starving`；`sema` 信号量。
  2. 正常模式：新来的 G 可自旋抢锁；唤醒的 waiter 不一定拿到锁，可能被新 G 抢走；吞吐高但可能饥饿。
  3. 饥饿模式：waiter 排队超过 1ms 进入；`Unlock` 直接把锁交给队首 waiter；队列为空或 waiter 拿到锁后退出。
  4. RWMutex：读锁共享，写锁独占；写锁等待时阻止新读锁，避免写饥饿；读锁不能递归（写者等待时递归读会死锁）。

- **对比**

  | 锁 | 行为 | 场景 |
  |---|---|---|
  | Mutex | 互斥 | 临界区 |
  | RWMutex | 多读单写 | 读多写少 |
  | atomic | 原子操作 | 简单计数/标志位 |

- **常见追问**
  - **Mutex 可以重入吗？** 不可以，重复 Lock 会死锁。
  - **为什么 RWMutex 读锁递归会死锁？** 写者等待时新读锁被阻塞，递归读锁也阻塞。
  - **什么时候用 atomic？** 简单计数、标志位，无复杂临界区。

## [必会] 10. WaitGroup / Once / Pool 的原理？

- **结论**：WaitGroup 用 counter + waiter 计数；Once 用 atomic + mutex 保证只执行一次；Pool 是 per-P 临时对象缓存，GC 会清理。

- **关键点**
  1. WaitGroup：`Add(delta)` 增加 counter，`Done = Add(-1)`，`Wait` 阻塞到 counter=0；不能复制；Add 必须在 Wait 之前。
  2. Once：`Do(f)` 先 atomic 检查 done，未完成则加锁执行；f panic 也视为完成。
  3. Pool：每个 P 有 private + shared 队列；Get 先取 private，再取 shared，再取其他 P；GC 时清空；适合临时对象复用，不保证命中。
  4. Cond：`Wait` / `Signal` / `Broadcast`，配合 Locker；用于条件等待。

- **常见追问**
  - **WaitGroup 为什么不能复制？** 内部包含 atomic 状态和 sema，复制会破坏状态。
  - **Pool 里的对象会被 GC 回收吗？** 会，Pool 不保证对象存活。
  - **Once 里 panic 会怎样？** 视为已执行，后续 `Do` 不再执行。

## [必会] 11. Go GC 的三色标记、写屏障、STW？

- **结论**：Go GC 是并发三色标记清扫，写屏障保证不漏标，STW 只发生在标记开始和结束。

- **关键点**
  1. 三色：白（未标记）、灰（可达未扫描）、黑（已扫描）；从根出发，灰变黑，引用变灰。
  2. 写屏障：并发标记时黑色对象引用白色对象会漏标；Go 1.8+ 混合写屏障（插入 + 删除），保证不丢对象。
  3. STW：mark setup（开启写屏障）和 mark termination（关闭写屏障、完成标记）两次短暂 STW；标记和清扫并发。
  4. 触发：堆增长到 GOGC 目标（默认 100，即翻倍）；2 分钟强制 GC；手动 `runtime.GC`。
  5. Go 1.19+ `GOMEMLIMIT` 软内存上限，配合 GOGC 控制。

- **常见追问**
  - **为什么需要写屏障？** 并发标记时对象图在变，防止漏标。
  - **Go GC 是分代/压缩的吗？** 不是分代，不是压缩；标记清扫，对象不移动。
  - **如何减少 GC 压力？** 减少堆分配、对象复用（sync.Pool）、调整 GOGC/GOMEMLIMIT、避免大对象。

## [必会] 12. 逃逸分析是什么？什么情况会逃逸？

- **结论**：编译器静态分析变量是否逃逸出函数；逃逸则分配在堆，否则栈。

- **关键点**
  1. 目标：减少堆分配和 GC 压力；栈分配随函数返回自动回收。
  2. 常见逃逸：返回局部变量指针、闭包捕获、interface 装箱、发送指针到 channel、存入全局/堆对象、对象过大。
  3. 查看：`go build -gcflags="-m"`，`-m -m` 更详细。
  4. 逃逸分析是编译器优化，不是语言规范；不要依赖它做正确性。

- **常见追问**
  - **`new(T)` 一定在堆上吗？** 不一定，可能栈分配。
  - **闭包一定逃逸吗？** 不一定，编译器可优化；但捕获变量通常逃逸。
  - **如何减少逃逸？** 返回值而非指针、避免不必要的 interface、预分配。

## [必会] 13. defer 执行顺序？defer 怎么修改返回值？recover 生效条件？

- **结论**：defer 后进先出；命名返回值可被 defer 修改；recover 只在 deferred function 中直接调用才生效。

- **关键点**
  1. defer 注册时求值参数；函数返回前逆序执行。
  2. 修改返回值：命名返回值 + 闭包；匿名返回值是拷贝，改局部变量无效。
  3. panic 流程：panic → 执行 defer → 未 recover 则程序崩溃；recover 停止 panic，函数正常返回。
  4. recover 只在 deferred function 中直接调用有效；在普通函数/嵌套函数中无效。
  5. defer 开销：Go 1.14+ open-coded defer，常见场景低开销；循环/动态 defer 仍堆分配。

- **示例**

  ```go
  func f() (x int) {
      defer func() { x++ }()
      return 1 // 返回 2
  }
  ```

- **常见追问**
  - **defer 中的变量是值还是引用？** 参数在注册时求值；闭包捕获变量本身。
  - **panic 后 recover 返回值是什么？** 函数返回当前命名返回值；未命名返回零值。
  - **子 goroutine panic 能 recover 吗？** 只能在该 goroutine 的 defer 中 recover，主 goroutine 无法捕获。
  - **Go 的错误处理怎么做？** 预期错误用 `error` 返回值，配合 `errors.Is/As` 和 `%w` 包装；`panic` 只用于不可恢复的程序错误。

## [必会] 14. context 的作用？WithCancel / WithTimeout / WithValue 的区别？

- **结论**：context 用于跨 goroutine 传递取消信号、超时和请求级数据；应作为函数第一个参数。

- **关键点**
  1. 接口：`Deadline`、`Done`、`Err`、`Value`。
  2. `WithCancel`：手动取消；`WithTimeout`：超时自动取消；`WithDeadline`：指定截止时间；`WithValue`：传请求级元数据。
  3. 取消传播：父 context 取消 → 所有子 context 取消；`Done` channel 关闭。
  4. 规范：不把 context 存 struct；不传 nil，用 `context.Background` / `TODO`；Value 只放请求级数据，不放可选参数。

- **常见追问**
  - **context 能强制杀死 goroutine 吗？** 不能，只能通知；goroutine 需主动检查 `Done` / `Err`。
  - **WithValue 的 key 用什么？** 自定义不可导出类型，避免冲突。
  - **context 会泄漏吗？** 忘记调用 cancel 会导致 timer/资源泄漏；WithTimeout/WithCancel 必须 `defer cancel()`。

- **项目挂载**：gRPC 的 deadline/取消通过 context 传递；项目里用 context 控制请求超时。

## [必会] 15. goroutine 泄漏的常见场景？data race 怎么检测？

- **结论**：泄漏是 goroutine 永久阻塞无法退出；data race 是并发读写同一变量且无同步；用 pprof 和 `-race` 检测。

- **关键点**
  1. 泄漏场景：向无缓冲/满缓冲 channel 发送但无人接收；从空 channel 接收但无人发送；select 没有 default 且无退出条件；死锁；忘记 cancel context；无限循环没有退出。
  2. 检测：`runtime.NumGoroutine()` 监控；pprof goroutine profile；`go test -race` / `go run -race`。
  3. data race：两个 goroutine 并发访问同一变量，至少一个写，且无同步；结果不确定。
  4. 解决：mutex/RWMutex、atomic、channel；明确变量所有权。
  5. 常见坑：for range 变量捕获（Go 1.22 前）、map 并发写、闭包引用循环变量。

- **常见追问**
  - **Go 1.22 的 for range 有什么变化？** 循环变量每轮新建，修复经典闭包坑。
  - **如何优雅退出 goroutine？** context + done channel；`close(done)` 广播。
  - **`-race` 能发现所有 race 吗？** 不能，只发现实际执行到的 race；需要测试覆盖。
