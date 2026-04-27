项目根目录：./blueking-dbm/dbm-services/common/dbha-v2

# 1. 协议

## 1.1 目标

- 新增`probe -> receiver`单向流式上报 RPC
   - 保留现有`PushData`

## 1.2 RPC定义

通信形式

## 1.3 消息模型

字段用途

- 采用`envelope + payload`
   - `envelope` 字段设计
      - `client_id` 客户端标识，跨重连不变；
         - 此处仍需关注 `client_id` 语义及生成机制。不可以是临时或随机短期值。
      - `sequence_id` 单 client 递增，保证数据最新；
      - `payload`
         - `HarvestData` 的 JSON bytes

# 2. 错误处理

错误预判 + 应对措施

1. 建立连接
2. 信息发送与传达
3. 资源限制

## 2.1 server


## 2.2 client


# 3. 监控告警

可观测性

## 日志

## 指标

### label

## 告警

具体场景

# 4. 待确认项：

流量治理、幂等与一致性