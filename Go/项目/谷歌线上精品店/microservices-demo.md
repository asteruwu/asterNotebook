# gRPC

## 概念

gRPC (gRPC Remote Procedure Calls) 是一个现代的、高性能的、开源的**远程过程调用 (RPC)** 框架。

- **RPC (远程过程调用):** 核心思想是让客户端程序可以像调用本地函数一样调用位于另一台机器上的服务函数，无需关心底层的网络通信细节。
- **服务/客户端模式:** gRPC 基于严格的服务契约，定义了客户端和服务端之间的交互方式。
- **跨语言支持:** gRPC 最大的优势之一是它能自动生成多种主流编程语言的代码，实现高效的**跨语言通信**。

| **支柱**                        | **描述**                                                     | **关键优势**                                                 |
| ------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **Protocol Buffers (Protobuf)** | 一种语言中立、平台中立、可扩展的序列化机制，用于定义数据结构和服务接口。 | **紧凑、高效**：序列化后的数据比 JSON/XML 小得多，传输更快。 |
| **HTTP/2**                      | gRPC 默认使用 HTTP/2 作为其传输协议。                        | **多路复用**：单个 TCP 连接可同时处理多个请求/响应流，消除了队头阻塞。**二进制帧**：数据以二进制形式传输，解析更高效。 |
| **接口定义语言 (IDL)**          | 使用 `.proto` 文件作为契约，严格定义了服务方法、参数和返回值。 | **强契约**：保证了客户端和服务端的兼容性，便于维护。**代码生成**：自动化生成样板代码。 |

## 工作流程

###  契约定义与代码生成

1. **定义契约：** 开发者在 `.proto` 文件中定义 `message`（数据结构）和 `service`（RPC 接口）。

2. **代码生成：** 使用 Protobuf 编译器 (`protoc`) 及其语言插件（如 `protoc-gen-go-grpc`），将 `.proto` 文件编译成目标语言（如 Go）的代码。

   - **服务端：** 生成一个服务接口 (Interface) 供开发者实现业务逻辑。

   - **客户端：** 生成一个客户端存根 (Stub/Client) 供客户端直接调用（`.pb.go`文件）。

```protobuf
// 服务端
// 需要在源码中实现这些远程调用方法
service CartService {
    rpc AddItem(AddItemRequest) returns (Empty) {}
    rpc GetCart(GetCartRequest) returns (Cart) {}
    rpc EmptyCart(EmptyCartRequest) returns (Empty) {}
}
```

```protobuf
// 数据结构
message CartItem {
    string product_id = 1;
    int32  quantity = 2;
}

message AddItemRequest {
    string user_id = 1;
    CartItem item = 2;
}
```

### 客户端发起调用

1. **调用本地存根：** 客户端代码调用生成的客户端存根上的方法，并传入参数。
2. **序列化：** 客户端存根利用 Protobuf 库将请求参数对象**序列化**成紧凑的二进制格式。
3. **HTTP/2 传输：** 客户端库将序列化后的二进制数据封装到 **HTTP/2 的数据帧**中，通过持久的 HTTP/2 连接发送给服务端。

> [!NOTE]
>
> 实际在进行远程调用的时候需要先创建客户端，代码片段如下。

1. 在服务端结构体中定义远程调用的服务的相关数据类型；

   ```go
   type cartService struct {
   	...
   	// 其他服务的地址、gRPC连接、远程调用服务客户端
   	productCatalogSvcAddr string
   	productCatalogSvcConn *grpc.ClientConn
   	productClient         pb.ProductCatalogServiceClient
   }
   ```

2. 连接到gRPC并创建所需要的远程调用客户端；

   ```go
   mustMapEnv(&srv.productCatalogSvcAddr, "PRODUCT_CATALOG_SERVICE_ADDR")
   mustConnGRPC(ctx, &srv.productCatalogSvcConn, srv.productCatalogSvcAddr)
   
   srv.productClient = pb.NewProductCatalogServiceClient(srv.productCatalogSvcConn)
   ```

   **关键要素**

   - 远程调用服务端的地址`SvcAddr`，从环境变量中读取；
   - 必要的gRPC连接`SvcConn`，用到`mustMapEnv`函数中赋值的远程调用服务端地址；
   - 当前上下文信息。

###  服务端处理请求

1. **HTTP/2 接收：** 服务端 gRPC 库接收到 HTTP/2 数据帧。
2. **反序列化：** 服务端 gRPC 库利用 Protobuf 库将二进制数据**反序列化**回服务端语言对应的请求对象。
3. **调用业务逻辑：** 服务端 gRPC 库调用开发者实现的业务逻辑方法（即实现了 Protobuf 接口的那个 `struct` 方法），传入反序列化后的请求对象。

> [!NOTE]
>
> 实际要先创建本服务的gRPC服务端，并且向gRPC注册服务，代码片段如下。

```go
grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)

// 注册服务
pb.RegisterCartServiceServer(grpcServer, srv)
// 通过gRPC进行服务的健康检查
healthpb.RegisterHealthServer(grpcServer, health.NewServer())
```

### 返回响应

1. **业务逻辑返回：** 业务逻辑执行完毕，返回响应对象。
2. **序列化与传输：** 服务端 gRPC 库将响应对象序列化，通过 HTTP/2 连接返回给客户端。
3. **客户端接收：** 客户端 gRPC 库接收响应数据并反序列化，最终将结果返回给客户端调用代码。

## 核心要素

### `.proto`文件

| **步骤**         | **关键点**                                                   | **目的/意义**                                         |
| ---------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| **数据结构定义** | `message`：定义请求（Request）和响应（Response）的数据结构。 | 确保跨语言数据传输的结构化和高效性。                  |
| **服务接口定义** | `service`：定义远程调用的函数（RPC 方法）。                  | 定义客户端能调用的 API 契约。                         |
| **代码生成**     | 编译命令：使用 `protoc` 工具生成特定语言（如 Go）的代码。    | 自动化生成客户端/服务端代码和数据结构，减少手动工作。 |

### 服务端实现

以Product Catalog为例，`.proto`文件中有这些`rpc`方法：

```protobuf
service ProductCatalogService {
    rpc ListProducts(Empty) returns (ListProductsResponse) {}
    rpc GetProduct(GetProductRequest) returns (Product) {}
    rpc SearchProducts(SearchProductsRequest) returns (SearchProductsResponse) {}
}
```

其中关键数据结构在`.proto`文件中的定义如下：

> type Product

```protobuf
message Product {
    string id = 1;
    string name = 2;
    string description = 3;
    string picture = 4;
    Money price_usd = 5;

    // Categories such as "clothing" or "kitchen" that can be used to look up
    // other related products.
    repeated string categories = 6;
}
```

在源码中一一实现，体现为：

> ListProducts

```protobuf
message ListProductsResponse {
    repeated Product products = 1; // 返回以Product为基本元素的切片
}
```

```go
func (p *productCatalog) ListProducts(context.Context, *pb.Empty) (*pb.ListProductsResponse, error) {
	time.Sleep(extraLatency) // 这个extraLatency应该是要从环境变量中读取的，得额外设置

	return &pb.ListProductsResponse{Products: p.parseCatalog()}, nil
	// 调用productCatalog的方法parseCatalog
	// 生成一个以*Product（存储了产品各种信息的结构体）为基本元素的切片，并赋给产品总列表Products
}
```
> GetProduct

```protobuf
message GetProductRequest {
    string id = 1;
}
```


```go
func (p *productCatalog) GetProduct(ctx context.Context, req *pb.GetProductRequest) (*pb.Product, error) {
	time.Sleep(extraLatency)

	var found *pb.Product
	for i := 0; i < len(p.parseCatalog()); i++ {
		if req.Id == p.parseCatalog()[i].Id {
			found = p.parseCatalog()[i]
		}
	}
	// 遍历产品列表切片
	// 如果Id匹配切片元素结构体下的Id就说明找到了，直接把这个结构体赋给found

	if found == nil {
		return nil, status.Errorf(codes.NotFound, "no product with ID %s", req.Id)
	}
	return found, nil
	// 要么返回found，要么就没找到
}
```

> SearchProducts

```protobuf
message SearchProductsRequest {
    string query = 1;
}

message SearchProductsResponse {
    repeated Product results = 1; // 返回以Product为基本元素的切片
}
```


```go
func (p *productCatalog) SearchProducts(ctx context.Context, req *pb.SearchProductsRequest) (*pb.SearchProductsResponse, error) {
	time.Sleep(extraLatency)

	var ps []*pb.Product // 定义一个以指向Product结构体的指针为元素的切片
	for _, product := range p.parseCatalog() {
		if strings.Contains(strings.ToLower(product.Name), strings.ToLower(req.Query)) ||
			strings.Contains(strings.ToLower(product.Description), strings.ToLower(req.Query)) {
			ps = append(ps, product)
		}
	}
	// 遍历产品列表切片
	// 如果Query（用户输入的查询信息，从SearchProductsRequest中读取）被当前遍历到的产品的名字或描述包含就返回true
	// true则把当前遍历到的product加到ps切片中
	// 最终ps会包含所有与可能与Query匹配的产品结构体

	return &pb.SearchProductsResponse{Results: ps}, nil
	// 把ps作为结果赋给SearchProductsResponse
}
```

> parseCatalog | 补充函数 |非远程调用

```go
func (p *productCatalog) parseCatalog() []*pb.Product {
	if reloadCatalog || len(p.catalog.Products) == 0 {
		err := loadCatalog(&p.catalog)
		if err != nil {
			return []*pb.Product{}
		}
	}
	// 如果产品列表为空或reload参数为真（用于调试）就调用loadCatalog函数，把产品信息存储到结构体下的产品列表切片中

	return p.catalog.Products
	// 返回总产品列表切片，包含从JSON文件中读取到的所有产品相关信息
}
```

> loadCatalog | 补充函数 | 非远程调用

```go
// 定义总逻辑，选择从本地文件加载产品信息/从外部数据库加载产品信息
// 加载信息的时候加锁，防止并发读写导致错误
func loadCatalog(catalog *pb.ListProductsResponse) error {
	catalogMutex.Lock()
	defer catalogMutex.Unlock()

	if os.Getenv("ALLOYDB_CLUSTER_NAME") != "" {
		return loadCatalogFromAlloyDB(catalog)
	}

	return loadCatalogFromLocalFile(catalog)
}

// 从本地文件/数据库加载产品信息的逻辑此处不作赘述
```

### 客户端调用

以Checkout调用Product Catalog Service为例，先创建gRPC连接：

> 在Checkout服务端结构体中定义相关数据

```go
type checkoutService struct {
	...

	productCatalogSvcAddr string
	productCatalogSvcConn *grpc.ClientConn

	...
}
```

> 获取Product Catalog Service的地址并存储gRPC连接

```go
mustMapEnv(&svc.productCatalogSvcAddr, "PRODUCT_CATALOG_SERVICE_ADDR")
mustConnGRPC(ctx, &svc.productCatalogSvcConn, svc.productCatalogSvcAddr)
```

将远程调用封装为服务本身实现的一个方法：

```go
// 此处用到的远程调用函数为GetProduct
func (cs *checkoutService) prepOrderItems(ctx context.Context, items []*pb.CartItem, userCurrency string) ([]*pb.OrderItem, error) {
	out := make([]*pb.OrderItem, len(items))
    // 创建远程调用客户端，通过客户端发起调用请求
	cl := pb.NewProductCatalogServiceClient(cs.productCatalogSvcConn)

	for i, item := range items {
        // 这里的GetProductId是自动生成的函数，用于返回CartItem结构体下Id的值
		product, err := cl.GetProduct(ctx, &pb.GetProductRequest{Id: item.GetProductId()})
		if err != nil {
			return nil, fmt.Errorf("failed to get product #%q", item.GetProductId())
		}
        // 同理，GetPriceUsd是自动生成的函数，用于返回Product结构体下的price_usd
		price, err := cs.convertCurrency(ctx, product.GetPriceUsd(), userCurrency)
		if err != nil {
			return nil, fmt.Errorf("failed to convert price of %q to %s", item.GetProductId(), userCurrency)
		}
        // 最终聚合到*pb.OrderItem，并生成切片
		out[i] = &pb.OrderItem{
			Item: item,
			Cost: price}
	}
	return out, nil
}
```

# OTel

## 组件

OpenTelemetry 提供了一套工具、API 和 SDK，用于采集服务的**三要素（Traces, Metrics, Logs）**。在 `microservices-demo` 中，它主要用于实现服务间的**分布式链路追踪**。

| **概念**                | **描述**                                                     | **在 microservices-demo 中的体现**                           |
| ----------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **Span**                | 代表服务中的一个工作单元，例如一个函数调用、一个 HTTP 请求或一个 gRPC 调用。 | 每一个 gRPC 调用、数据库操作、Redis 交互等，都对应一个 Span。 |
| **Trace**               | 一组 Span 组成的树形结构，表示一个完整的请求（从开始到结束）在所有服务间的流向。 | 用户从前端到结账的整个流程，就是一个完整的 Trace。           |
| **Context Propagation** | 将当前的 Trace ID 和 Span ID 从一个服务传递到下一个服务。这是链路追踪的关键。 | **重点：** OTel 库将 Trace/Span ID 注入到 gRPC 调用的 **Metadata** 中进行传输。 |
| **Exporter**            | 负责将采集到的 Span 数据发送到后端存储系统（如 Jaeger, Zipkin, Prometheus）。 | 在 `microservices-demo` 中，通常会将数据发送给 **OTel Collector**，然后由 Collector 转发到 Jaeger 等系统。 |

<img src="../../../dio图表/MicroService/总体架构-OTel.drawio.svg" alt="总体架构-OTel.drawio" style="zoom:80%;" />

## 集成原理

1. **客户端发起调用请求**

   - 在 gRPC 客户端代码执行远程调用前，OTel 拦截器（Interceptor）会调用Tracer创建一个新的 **Span**。
   - 这个 Span 的 Context（包含 Trace ID 和 Span ID）会被 OTel 库（Propagator隐式实现）注入到 gRPC 请求的 **Metadata** 中。
   - Metadata 随 HTTP/2 请求头发送出去。

2. **服务端接收远程调用请求**

   - 在 gRPC 服务端接收到请求后，OTel 拦截器会先运行。

   - 它调用Propagator隐式地从请求的 Metadata 中提取出 Trace Context。

   - 它调用Tracer创建一个新的 **Span**，并将其设置为从 Metadata 中提取的 Span 的子 Span（Child Span）。

   - 后续的业务逻辑（如调用 Redis、调用数据库）都在这个新的 Span 下创建子 Span。

3. **Go 语言实现细节：**

   - **OTel SDK 初始化：** 项目启动时需要初始化 OTel SDK，配置 **Resource**（服务名称等元信息）和 **Exporter**。

   - **拦截器（Interceptor）：** Go gRPC 客户端使用 `grpc.WithStatsHandler(otelgrpc.NewClientHandler()`，服务端使用 `grpc.StatsHandler(otelgrpc.NewServerHandler()`，来插入 OTel 的处理逻辑。


## Trace

链路追踪初始化任务：

通信协议：**gRPC**

- 设置数据收集器Collector
- 创建Tracer生成器TracerProvider：
  - 数据导出器Expoter
  - 采样器Sampler

```go
func initTracing() error {
	var (
		collectorAddr string
		collectorConn *grpc.ClientConn
	)

	ctx := context.Background()

	mustMapEnv(&collectorAddr, "COLLECTOR_SERVICE_ADDR")
	mustConnGRPC(ctx, &collectorConn, collectorAddr)

	exporter, err := otlptracegrpc.New(
		ctx,
		otlptracegrpc.WithGRPCConn(collectorConn))
	if err != nil {
		log.Warnf("warn: Failed to create trace exporter: %v", err)
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithSampler(sdktrace.AlwaysSample()))
	otel.SetTracerProvider(tp)
	return err
}
```

# middleware

<img src="../../../dio图表/MicroService/Frontend.drawio.svg" alt="Frontend.drawio" style="zoom:150%;" />

```go
// 初始指向路由器r
var handler http.Handler = r
// 将r包裹在日志中间件中
handler = &logHandler{log: log, next: handler} // add logging
// 将以上整体包裹在Session中间件中
handler = ensureSessionID(handler) // add session ID
// 将整体包裹在 OpenTelemetry 追踪中间件中
handler = otelhttp.NewHandler(handler, "frontend") // add OTel tracing
```

## responseRecorder

一个辅助结构体，用于“窃听”并记录原本直接发给客户端的响应信息。

**接口装饰模式**

- 它通过嵌入 `w http.ResponseWriter` 并重写 `Write` 和 `WriteHeader` 方法，实现了标准的 `http.ResponseWriter` 接口。
- **拦截**：当业务逻辑调用 `Write` 发送数据时，它不仅调用原本的 `w.Write`，还顺手把字节数加到自己的 `b` 字段，把状态码存入 `status` 字段。

```go
// 定义数据结构
type responseRecorder struct {
	b      int
	status int
	w      http.ResponseWriter
}

// 实现Write方法
func (r *responseRecorder) Write(p []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	n, err := r.w.Write(p)
	r.b += n
	return n, err
}

// 实现WriteHeader方法
func (r *responseRecorder) WriteHeader(statusCode int) {
	r.status = statusCode
	r.w.WriteHeader(statusCode)
}
```

## logHandler

**核心逻辑**

- **前置处理**：生成 RequestID，创建开始时间戳 (`start`)，初始化结构化日志对象。
- **执行控制**：创建 `responseRecorder` 替换原始的 `ResponseWriter`，然后调用 `lh.next.ServeHTTP(rr, r)` 放行请求。
- **后置处理**：利用 `defer` 机制，在 `next` 执行完毕（即栈回溯）时，计算耗时 (`time.Since`)，并从 `responseRecorder` 中提取最终的状态码和字节数写入日志。

```go
func (lh *logHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 创建一个新的context，并且在其中附带上当前请求ID的键值对（方便写日志时从context中取出，如下文所示）
	ctx := r.Context()
	requestID, _ := uuid.NewRandom()
	ctx = context.WithValue(ctx, ctxKeyRequestID{}, requestID.String())

	// 开始计时
	start := time.Now()

	// 将当前请求的回应器注入给rr中的ResponseWriter
	rr := &responseRecorder{w: w}

	// 创建结构化日志，定义要写入日志的信息
	log := lh.log.WithFields(logrus.Fields{
		"http.req.path":   r.URL.Path,
		"http.req.method": r.Method,
		"http.req.id":     requestID.String(),
	})

	// 获取当前contextID，同样写入结构化日志中
	if v, ok := r.Context().Value(ctxKeySessionID{}).(string); ok {
		log = log.WithField("session", v)
	}
	log.Debug("request started")

	// 注册延迟执行函数，能够等到函数所有逻辑执行完毕再执行以下计时逻辑，并且写入结构化日志
	defer func() {
		log.WithFields(logrus.Fields{
			"http.resp.took_ms": int64(time.Since(start) / time.Millisecond),
			"http.resp.status":  rr.status,
			"http.resp.bytes":   rr.b}).Debugf("request complete")
	}()

	// 生成新context然后附加log相关的键值对
	ctx = context.WithValue(ctx, ctxKeyLog{}, log)
	// 更新Request中的context
	r = r.WithContext(ctx)
	// 接着实现next传入的下一个接口的ServeHTTP方法（将更新过context信息的request传递给下一层）
	lh.next.ServeHTTP(rr, r)
}
```

## ensureSessionID

负责业务前置检查和上下文填充。

**核心逻辑**

- **检查与生成**：先看 Cookie 有没有 ID，没有就生成（或读取环境变量）。
- **上下文 `Context`传递**：这是 Go 语言最精髓的设计。它使用 `context.WithValue` 将 `sessionID` 注入到请求的 Context 中，生成一个新的 `http.Request`。
- **隐式传递**：后续所有的处理函数（Controller/Service）不需要在函数参数里写 `sessionID string`，直接从 `r.Context()` 里取即可。

**价值**

- 为每个请求打上用户标签，使得后续的日志、监控、限流都可以基于 User/Session 维度进行。

```go
func ensureSessionID(next http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var sessionID string
		// 从当前请求的Cookie中读取SessionID并存储
		c, err := r.Cookie(cookieSessionID)
		// 错误处理逻辑，Cookie没有的话就从环境变量读取硬编码的SessionID，这个也没有的话就随机生成一个
		if err == http.ErrNoCookie {
			if os.Getenv("ENABLE_SINGLE_SHARED_SESSION") == "true" {
				// Hard coded user id, shared across sessions
				sessionID = "12345678-1234-1234-1234-123456789123"
			} else {
				u, _ := uuid.NewRandom()
				sessionID = u.String()
			}
			// 生成以后再注入到Cookie中
			http.SetCookie(w, &http.Cookie{
				Name:   cookieSessionID,
				Value:  sessionID,
				MaxAge: cookieMaxAge,
			})
		} else if err != nil {
			return
		} else {
			sessionID = c.Value
		}
		// 生成新context并附加上SessionID的键值对
		ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
		// 更新当前request中的context
		r = r.WithContext(ctx)
		// 然后接着实现next传入的下一个接口的ServeHTTP方法（将更新过context信息的request传递给下一层）
		next.ServeHTTP(w, r)
	}
}
```

---

HTTP 协议设计为**无状态协议**。这意味着每个 HTTP 请求都是独立的事务，服务器默认不会保留两个请求之间的任何上下文信息。为了在无状态的协议之上构建有状态的应用（Stateful Application，如购物车、用户登录），必须引入**状态管理机制**，即 Cookie 和 Session。

### Session

Session 是**服务器端**维护的一个逻辑实体，用于存储特定用户在一段交互时间内的上下文数据。

**工作原理**：

1. **标识**：每个 Session 都有一个全局唯一的标识符，称为 **Session ID**。
2. **关联**：服务器通过 Session ID 将客户端的请求与存储在服务端的会话数据关联起来。
3. **载体**：Session ID 通常通过 Cookie 在客户端和服务端之间传递（即 Cookie 中存储的值就是 Session ID）。

**生命周期**：

- **创建**：用户首次访问或登录时生成。
- **存活**：通过滑动窗口机制（每次交互刷新过期时间）或固定 TTL (Time To Live) 维持。
- **销毁**：用户主动登出或 TTL 过期。

### Cookie

Cookie 是由服务器发送给客户端（通常是浏览器）的一小块数据，**客户端**会在后续对同一服务器的请求中**自动携带**该数据。

**传输机制**：

- **下发**：服务器在 HTTP **响应头 (Response Header)** 中包含 `Set-Cookie` 字段。
- **回传**：客户端在后续的 HTTP **请求头 (Request Header)** 中包含 `Cookie` 字段，将数据回传给服务器。

**架构属性**：

- **存储位置**：客户端（User Agent）。
- **容量限制**：通常限制在 4KB 以内，不适合存储大量数据。
- **域与路径 (Scope)**：通过 `Domain` 和 `Path` 属性控制 Cookie 的作用域，实现跨子域共享或路径隔离。

![Frontend-Session&Cookie.drawio](../../../dio图表/MicroService/Frontend-Session&Cookie.drawio.svg)

# CartService | Rewrite by Go

## 架构分层与解耦

**核心目标**：将**业务逻辑**与**数据存储**实现彻底分离。

**关键实现**：

- **定义抽象接口**： 不直接在 Service 层操作 Redis 客户端，而是定义一个 `ICartRepository` 接口，描述“我们需要做什么”（AddItem, GetCart），而不关心“怎么做”。

  ```go
  type ICartRepository interface {
  	AddItem(ctx context.Context, userID string, item *pb.CartItem) error
  	GetCart(ctx context.Context, userID string) ([]*pb.CartItem, error)
  	EmptyCart(ctx context.Context, userID string) error
  }
  ```

- **依赖注入**： 在 `main.go` 组装服务时，将具体的 Redis 实现注入到 Service 中。这使得未来替换存储引擎（如换成 MySQL）或进行单元测试（注入 Mock 结构体）时，无需修改核心业务代码。

  ```go
  // cartService 持有接口而非具体结构体
  type cartService struct {
      pb.UnimplementedCartServiceServer
      repo repository.ICartRepository // <--- 接口类型
      // ...
  }
  
  func main() {
      // 1. 初始化具体的存储实现
      cr, _ := repository.NewCartRedis()
      // 2. 注入到 Service 中
      srv := NewCartService(cr)
      // ...
  }
  ```

- **原子性操作**： 在 Redis 实现层，利用 Redis 原生指令保证数据一致性，避免应用层的并发冲突。

  ```go
  func (r *CartRedis) AddItem(ctx context.Context, userID string, item *pb.CartItem) error {
      key := fmt.Sprintf("cart:%s", userID)
      // 直接利用 Redis 原子指令进行累加，线程安全且高效
      return r.rdb.HIncrBy(ctx, key, item.ProductId, int64(item.Quantity)).Err()
  }
  ```

## 全链路超时控制

**核心目标**：实现**快速失败 Fail-fast** 机制。防止因 Redis 故障或网络拥堵导致请求线程阻塞，进而耗尽资源引发级联故障 Cascading Failure。

**关键实现**：

- **Context 传递与派生**： 利用 `context.WithTimeout` 创建带有截止时间的子 Context，并强制将其一路传递到最底层的数据层。
- **错误语义区分**： 精确区分“超时错误”与“内部错误”，帮助快速定位是性能问题`timeout`还是功能故障`internal`。

> Service层控制

```go
// 定义 SLA：服务端兜底超时时间
const cartTimeout = 500 * time.Millisecond

func (s *cartService) GetCart(ctx context.Context, req *pb.GetCartRequest) (*pb.Cart, error) {
    // 1. 派生带超时的 Context，确保 500ms 后释放资源
	childCtx, cancel := context.WithTimeout(ctx, cartTimeout)
    // 确保release资源
	defer cancel()
    
    // 2. 将 childCtx 传给 repo
	cartItems, err := s.repo.GetCart(childCtx, req.UserId)
	if err != nil {
        // 3. 精准映射错误码
		if err == context.DeadlineExceeded {
            // 返回 gRPC 标准超时错误码
			return nil, status.Error(codes.DeadlineExceeded, "[timeout]Failed to get cart for user")
		}
		return nil, status.Error(codes.Internal, "[internal]Failed to get cart for user")
	}
	cart := &pb.Cart{UserId: req.UserId, Items: cartItems}
	return cart, nil
}
```

> 数据层执行

```go
// Redis 客户端接收 ctx，如果 ctx 超时，go-redis 会自动取消请求并返回错误
func (r *CartRedis) GetCart(ctx context.Context, userID string) ([]*pb.CartItem, error) {
	key := fmt.Sprintf("cart:%s", userID)
	data, err := r.rdb.HGetAll(ctx, key).Result()
	// ...
	return cartItems, nil
}
```

## 高并发数据组装

**核心目标**：优化 **P99 延迟**。利用 Scatter-Gather（分散-收集）模式，并行调用外部依赖（如商品服务），将串行耗时变为并行耗时。

**关键实现**：

- **ErrGroup 并发编排**： 使用 `golang.org/x/sync/errgroup` 管理并发任务。它比原始的 `WaitGourp` 更强大，能自动传播 Context 取消信号，并捕获第一个发生的错误。
- **无锁并发安全**： 利用“预分配 Slice + 索引写入”的技巧，避免了在并发写入结果集时使用互斥锁 (`Mutex`)，最大限度降低竞争开销。
- **闭包陷阱处理**： 在 `for` 循环启动 Goroutine 时，正确处理了循环变量的捕获问题，防止所有 Goroutine 都在处理最后一个元素。

```go
func (s *cartService) GetCartWithDetails(ctx context.Context, req *pb.GetCartRequest) ([]*CartItemWithDetails, error) {
    items, _ := s.repo.GetCart(ctx, req.UserId)

    // 1. 创建 Group，继承父 Context 的超时和 Trace 特性
    g, groupCtx := errgroup.WithContext(ctx)
    
    // 2. 预分配结果切片，利用 index 实现无锁写入
    results := make([]*CartItemWithDetails, len(items))

    for i, item := range items {
        // 3. 关键：解决循环变量捕获问题
        index, value := i, item 
        
        g.Go(func() error {
            // 4. 并行调用商品服务
            // 注意这里使用 groupCtx，一旦有一个失败，其他请求也会感知到 Cancel
            product, err := s.productClient.GetProduct(groupCtx, &pb.GetProductRequest{Id: value.ProductId})
            if err != nil {
                return fmt.Errorf("failed to get product details: %+v", err)
            }
            
            // 5. 通过 index 写入对应的位置，完全不需要 Lock
            results[index] = &CartItemWithDetails{
                ProductID:   value.ProductId,
                Quantity:    value.Quantity,
                Name:        product.Name,
                // ...
            }
            return nil
        })
    }

    // 6. 等待所有任务完成
    if err := g.Wait(); err != nil {
        return nil, err
    }
    return results, nil
}
```

# Docker / K8s

## Dockerfile

### 多阶段构建

将“编译环境”和“运行环境”分离，避免将庞大的 Go 编译器 (`go toolchain`) 带入生产环境。

- **原理**：

  - **第一阶段 (Builder)**：使用全量的 Go 环境 (`golang:alpine`) 进行依赖下载和代码编译 。
  - **第二阶段 (Runner)**：使用最小的基础镜像 (`alpine:latest`)，仅从第一阶段拷贝编译好的二进制文件 。

  ```dockerfile
  FROM golang:1.24.0-alpine AS builder
  # ...
  FROM alpine:latest
  ```

### 构建层缓存优化 

利用 Docker 的分层存储机制来加速构建过程。

- **技巧**：先拷贝依赖描述文件 (`go.mod`, `go.sum`) 并下载依赖，**然后再**拷贝源代码。

  ```dockerfile
  COPY go.mod .
  COPY go.sum .
  
  # 只要 go.mod 没变，这一层就会被缓存，无需重新下载依赖
  RUN go mod download 
  
  COPY . .
  ```

### 静态编译

为了确保 Go 程序在极简的 Alpine 系统中也能运行，必须处理 C 库依赖问题。

- **关键指令**：

  ```dockerfile
  RUN CGO_ENABLED=0 # ...
  ```

- **原理**：

  - Go 默认可能链接 `glibc` (标准 Linux C 库)。
  - Alpine Linux 使用的是更小的 `musl libc`。如果不禁用 CGO，编译出的程序在 Alpine 上可能报错 `no such file or directory`。

  - `CGO_ENABLED=0` 强制 Go 进行静态编译，将所有依赖打包进二进制文件，使其不依赖系统的动态链接库。

### 完整示例

```dockerfile
# [Stage 1: Builder]
# 明确指定版本，保证构建可复现
FROM golang:1.24.0-alpine AS builder
WORKDIR /app

# 优化缓存：先下依赖，后拷源码
COPY go.mod .
COPY go.sum .
RUN go mod download

COPY . .

# 静态编译关键参数：禁用 CGO，指定目标系统 Linux
RUN CGO_ENABLED=0 GOOS=linux go build -o cartservice . 

# [Stage 2: Runner]
# 使用最小镜像
FROM alpine:latest

WORKDIR /app

# 关键：只拷贝二进制文件，丢弃源码和编译器
COPY --from=builder /app/cartservice . 

# 声明端口（仅作为文档说明，不具备强制性）
EXPOSE 7070

# 容器启动命令
CMD ["./cartservice"]
```

## Collector Pipeline

通过`monitoring.yml` 文件定义了一个经典的 OpenTelemetry (OTel) Collector 部署架构。它是整个可观测性系统的**心脏**，负责接收数据、处理数据并将其分发到不同的后端。

### ConfigMap

ConfigMap 存储了 Collector 的配置文件 `otel-collector-config.yaml`。这个配置文件定义了数据处理的流水线（Pipeline）。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-conf
data:
  otel-collector-config: |
```

- **Receivers (接收器)**: 定义了 Collector 如何**接收**数据。

  - `otlp`: 使用 OpenTelemetry 原生协议 (OTLP) 接收数据。

  - `protocols`:
    - `grpc`: 监听 `0.0.0.0:4317`。这是最高效的方式，`cartservice` 等微服务通常通过这个端口发送数据。
    - `http`: 监听 `0.0.0.0:4318`。用于支持 HTTP 协议的客户端。

  ```yaml
  receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
  ```

- **Processors (处理器)**: 定义了在导出数据前如何**处理**数据。

  - `batch`: 这是一个非常关键的处理器。它不会每收到一条数据就发送，而是将数据积攒一小段时间（比如 200ms）或积攒一定数量（比如 100 条）打包发送。这能极大降低网络开销和后端压力。

  ```yaml
  processors:
        batch:
  ```

- **Exporters (导出器)**: 定义了数据要**发送**到哪里。

  - `prometheus`:
    - `endpoint: "0.0.0.0:8889"`: 这里不是“发送”数据，而是**开启一个服务端口**（8889），等待 Prometheus 来“拉取” (Scrape) 指标数据。
  - `otlp`:
    - `endpoint: "jaeger:4317"`: 这里是主动**推送** (Push) 数据。它将 Trace 数据发送给 K8s 集群中名为 `jaeger` 的 Service 的 4317 端口。
    - `tls: insecure: true`: 因为是在集群内部通信，且 Jaeger 默认没配 TLS，所以这里禁用了 TLS 验证。

  ```yaml
  exporters:
        prometheus:
          endpoint: "0.0.0.0:8889"
          namespace: "default"
        otlp:
          endpoint: "jaeger:4317"
          tls:
            insecure: true
  ```

- **Service Pipelines (服务流水线)**: 这里是将上述组件**组装**起来的地方。

  - **metrics (指标流水线)**:
    - 路径：`receivers [otlp]` -> `processors [batch]` -> `exporters [prometheus]`
    - 含义：通过 OTLP 接收指标，打包处理后，暴露给 Prometheus 拉取。
  - **traces (链路流水线)**:
    - 路径：`receivers [otlp]` -> `processors [batch]` -> `exporters [otlp]`
    - 含义：通过 OTLP 接收 Trace，打包处理后，通过 OTLP 协议转发给 Jaeger。

  ```yaml
  service:
        pipelines:
          metrics:
            receivers: [otlp]
            processors: [batch]
            exporters: [prometheus]
          traces:
            receivers: [otlp]
            processors: [batch]
            exporters: [otlp]
  ```

### Deployment

Deployment 定义了 Collector 如何在 Kubernetes 中运行。

- **Image (镜像)**:

  - 使用 `otel/opentelemetry-collector-contrib:0.88.0`。

  - `contrib` 包含了更多社区贡献的接收器和导出器（比如 Prometheus exporter），功能更全。

- **Args (启动参数)**:
  - `--config=/conf/otel-collector-config.yaml`: 告诉 Collector 启动时去哪里读取配置文件。

- **Ports (容器端口)**:

  - `4317`: OTLP gRPC 接收端口。

  - `4318`: OTLP HTTP 接收端口。

  - `8889`: Prometheus Metrics 暴露端口。

- **Volumes & Mounts (挂载配置)**:

  - 这里使用了一个技巧：将 Kubernetes 的 `ConfigMap` (`otel-collector-conf`) 挂载为容器内的一个文件 (`/conf/otel-collector-config.yaml`)。

  - 这样实现了**配置与代码解耦**。修改配置只需改 ConfigMap 并重启 Pod，不需要重新打镜像。

```yaml
template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
      - name: otel-collector
        image: otel/opentelemetry-collector-contrib:0.88.0
        args: ["--config=/conf/otel-collector-config.yaml"]
        ports:
        - containerPort: 4317
        - containerPort: 4318
        - containerPort: 8889
        volumeMounts:
        - name: otel-collector-config-vol
          mountPath: /conf
      volumes:
      - name: otel-collector-config-vol
        configMap:
          name: otel-collector-conf
          items:
          - key: otel-collector-config
            path: otel-collector-config.yaml
```

### Service

Service 定义了其他服务（如 `cartservice` 和 `prometheus`）如何访问 Collector。

- **Ports (服务端口)**:

  - `name: grpc, port: 4317`: 暴露给应用服务（如 `cartservice`）。微服务将数据推送到 `otel-collector:4317`。

  - `name: prometheus, port: 8889`: 暴露给 Prometheus。Prometheus 会访问 `otel-collector:8889/metrics` 来拉取数据。

  ```yaml
  spec:
    ports:
    - name: grpc
      port: 4317
      targetPort: 4317
    - name: prometheus
      port: 8889
      targetPort: 8889
  ```

- **Selector (选择器)**:
  - `app: otel-collector`: 确保流量只转发给带有此标签的 Deployment Pod。

