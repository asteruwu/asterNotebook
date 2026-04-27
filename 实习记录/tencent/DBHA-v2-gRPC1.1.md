# DBHA-v2 gRPC 直连通道功能扩展设计文档

项目根目录：./blueking-dbm/dbm-services/common/dbha-v2

# 0. 需求与目标

1. **接口定义**

   - **协议**
      
      新增单向流 RPC 方法（保留旧 PushData，兼容现有逻辑）；server 不返回业务响应

   - **消息体字段结构**
   
      采用 envelope + payload 结构：
      
      - envelope 携带 client_id、send_time；
      - payload 为 HarvestData 的 JSON 序列化；
      - receiver 复用现有反序列化逻辑

2. **server 端连接管理**

   - **连接数**
      
      - 最大连接数可在配置中设置；
      - 达到上限后拒绝新连接并告警；

   - **可观测性**

      - 全局统计连接总数；
      - 接收消息数、接收字节数、错误数按 client_id label 分组，暴露为 Prometheus metrics；
      - 队列满时丢弃消息，记录丢弃次数并监控，达到阈值告警；

3. **错误处理**

   - **client**

      - 连接错误

         - client 可从错误中区分「连接数超限」与其他错误以决定后续行为；
         - **连接数超限**：待考虑
         - 其他错误：沿用现有指数退避重连；

      - 消息发送错误
      
         - 重试；达到最大重复次数后丢弃并告警记录；

   - **server**

      - 连接错误

         - 接收失败记录日志并关闭当前连接，不影响其他连接。
