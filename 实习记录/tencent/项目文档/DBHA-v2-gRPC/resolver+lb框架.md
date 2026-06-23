# 示例代码

```go
// NewReceiverClient creates a ReceiverClient connected to the given endpoints.
func NewReceiverClient(ctx context.Context, endpoint string, clientId string) (*ReceiverClient, error) {
	pingTime := config.Cfg.Client.PingTime
	if pingTime <= 0 {
		pingTime = constant.DefaultClientPingTime
	}
	pingTimeout := config.Cfg.Client.PingTimeout
	if pingTimeout <= 0 {
		pingTimeout = constant.DefaultPingTimeout
	}
	maxRecvMsgSize := config.Cfg.Client.MaxReceiveMessageSize
	if maxRecvMsgSize <= 0 {
		maxRecvMsgSize = constant.DefaultMaxReceiveMessageSize
	}
	maxSendMsgSize := config.Cfg.Client.MaxSendMessageSize
	if maxSendMsgSize <= 0 {
		maxSendMsgSize = constant.DefaultMaxSendMessageSize
	}

	kacp := keepalive.ClientParameters{
		Time:                pingTime,
		Timeout:             pingTimeout,
		PermitWithoutStream: true,
	}

	eps, err := hanet.ParseList(endpoint, "tcp")
	if err != nil {
		return nil, gerrors.Newf(gerrors.InvalidConfiguration, "invalid receiver endpoint(%s): %s", endpoint, err)
	}

	addrs := make([]resolver.Address, 0, len(eps))
	for _, ep := range eps {
		addrs = append(addrs, resolver.Address{Addr: ep.HostPort()})
	}

	rs := manual.NewBuilderWithScheme(resolverScheme)
	rs.InitialState(resolver.State{Addresses: addrs})

	serviceConfig := `{"loadBalancingPolicy":"` + loadBalancingPolicy + `"}`

	conn, err := grpc.NewClient(
		resolverScheme+":///receiver",
		grpc.WithResolvers(rs),
		grpc.WithDefaultServiceConfig(serviceConfig),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithKeepaliveParams(kacp),
		grpc.WithDefaultCallOptions(
			grpc.MaxCallRecvMsgSize(maxRecvMsgSize),
			grpc.MaxCallSendMsgSize(maxSendMsgSize),
		),
	)

	if err != nil {
		logger.Error("failed to new grpc client, errmsg: %s", err)
		return nil, gerrors.New(gerrors.GrpcFailure, err.Error())
	}

	ctxBase, cancel := context.WithCancel(ctx)

	r := &ReceiverClient{
		clientId: clientId,
		conn:     conn,
		client:   proto.NewReceiverServiceClient(conn),
		resolver: rs,
		ctx:      ctxBase,
		cancel:   cancel,
	}

	return r, nil
}
```

这段代码详细展示了一个 `receiver client` 的初始化流程，包括构造连接参数、创建 gRPC 连接、返回客户端实例，以及本文档重点关注的 gRPC 框架自带的 **resolver + loadBalancer** 构造与使用。

# 角色定位

```go
// Resolver: manual.Builder
rs := manual.NewBuilderWithScheme(resolverScheme)
rs.InitialState(resolver.State{Addresses: addrs})

// Load Balancer: round_robin（通过 service config 声明）
serviceConfig := `{"loadBalancingPolicy":"` + loadBalancingPolicy + `"}`
```

- `Resolver`
  
  `manual` 意为**地址不靠 DNS 或注册中心自动发现，而是由调用方手动提供**。地址列表在启动时由配置文件里的 endpoint 解析而来，之后可以通过代码主动推送更新。

- `Load Balancer`
  
  用的是 `round_robin`，由 `service config` 字符串声明，gRPC 内部会根据这个字符串找到对应的 `Balancer` 工厂并实例化。

二者的职责边界非常清晰，即：

- `resolver` 负责地址的发现与推送；

- `Load Balancer` 负责地址的状态维护（`SubConn`）并决定每次 RPC 调用选择哪个地址。

# 协作机制

## 初始化

```go
eps, err := hanet.ParseList(endpoint, "tcp")
addrs := make([]resolver.Address, 0, len(eps))
for _, ep := range eps {
    addrs = append(addrs, resolver.Address{Addr: ep.HostPort()})
}

rs := manual.NewBuilderWithScheme(resolverScheme)
rs.InitialState(resolver.State{Addresses: addrs})   // ← 关键
```
`InitialState` 的作用是在 Dial 之前就把初始地址"预埋"进去。这样当 `grpc.NewClient` 触发 `Resolver` 的 `Build()` 时，`Balancer` 能立刻拿到地址列表，不需要等待一次异步解析。

```go
conn, err := grpc.NewClient(
		resolverScheme+":///receiver",                   // ← scheme 决定用哪个 Resolver
  		grpc.WithResolvers(rs),                          // ← 注册这个 manual Builder
		grpc.WithDefaultServiceConfig(serviceConfig),    // ← 决定用哪个 Balancer
        // ...
)
```
`grpc.NewClient` 内部的初始化链：

```
NewClient("manual:///receiver")
    │
    ├─ 根据 scheme "manual" 找到 rs 这个 Builder
    │
    ├─ 调用 rs.Build() → 返回一个 Resolver 实例
    │       └─ 立刻把 InitialState 里的地址推给 ClientConn
    │
    ├─ ClientConn 收到地址 → 找到 round_robin Balancer
    │
    └─ Balancer.UpdateClientConnState([A, B, C])
            └─ 为每个地址创建 SubConn（此时还不建立 TCP，lazy connect）
```

## 运行时

![示意图](../../../../dio图表/SRE/DBHA-v2-运行时%20resolver&loadBalancer.drawio.svg)

# 具体场景分析

