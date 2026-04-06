> [!IMPORTANT]
>
> 三次握手（3-way handshake）就是确保通信双方**发送能力和接收能力都正常**的过程。



![TCP_IP.dio-TCP三次握手.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\TCP_IP.dio-TCP三次握手.drawio.svg)



**背景**：客户端（小明）想与服务器（淘宝服务器）建立连接

# 第一次握手-SYN 同步请求

- **动作**：小明发送一个`SYN=1`的包（包含初始序列号`seq=x`）
- **含义**："你好，我想和你建立连接，我的初始号码是x"
- **类比**：小明拨打淘宝客服电话，说"喂，能听到吗？"（只证明小明能发送）



# 第二次握手-**SYN+ACK（同步确认）**

- **动作**：服务器回复`SYN=1`, `ACK=1`的包（包含自己的序列号`seq=y`，确认号`ack=x+1`）
- **含义**："收到你的请求了，我的初始号码是y，下次请从x+1开始发"
- **类比**：客服回答："能听到，您请讲。"（证明客服能接收+发送）



# 第三次握手-**ACK（最终确认）**

- **动作**：小明发送`ACK=1`的包（`seq=x+1`, `ack=y+1`）
- **含义**："好的，我们正式通信吧"
- **类比**：小明说："好的，我要咨询..."（证明小明能接收）



> [!NOTE]
>
> 序列号作用：就像对话中的"第X句话"，防止网络延迟导致的数据包混乱。



# 实践操作

与百度建立连接，并且使用`tcpdump`捕获TCP三次握手过程的数据包详情。

```shell
#终端1
dantalion@Dantalion:/$ sudo tcpdump -i eth0 -nn port 80

tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
```

> [!NOTE]
>
> `-i eth0`表示监听有线网卡（类型为以太网）的所有流量；
>
> `-nn`表示禁用主机名和端口号解析，直接输出原始IP和端口号；
>
> `port 80`表示只抓取80端口的流量。

```shell
#终端2
dantalion@Dantalion:~$ curl www.baidu.com
<!DOCTYPE html>
...
```

> [!NOTE]
>
> 此操作意在触发TCP连接。

```shell
#终端1

#第一次握手 Flags [S]：SYN 标志（发起连接）
#seq 2725176809：客户端初始序列号（ISN）
14:55:47.482850 IP 172.18.204.191.42890 > 183.2.172.17.80: Flags [S], seq 2725176809, win 64240, options [mss 1460,sackOK,TS val 628821458 ecr 0,nop,wscale 7], length 0

#第二次握手 Flags [S.]：SYN-ACK 标志（S 表示同步，. 表示 ACK）
#seq 2653864836：服务端初始序列号
#ack 2725176810：确认号 = 客户端 ISN + 1（2725176809 + 1）
14:55:47.491675 IP 183.2.172.17.80 > 172.18.204.191.42890: Flags [S.], seq 2653864836, ack 2725176810, win 8192, options [mss 1452,sackOK,nop,nop,nop,nop,nop,nop,nop,nop,nop,nop,nop,wscale 5], length 0

#第三次握手 Flags [.]：ACK 标志（确认包）
#ack 1：确认号 = 服务端 ISN + 1（2653864836 + 1，但显示为相对值 1）
14:55:47.491775 IP 172.18.204.191.42890 > 183.2.172.17.80: Flags [.], ack 1, win 502, length 0
```



# 必要性

- **同步双方序列号**：通过三次握手的过程，客户端和服务器能确认彼此的初始序列号，从而保证数据传输的顺序和可靠性。
- **确认双方准备就绪**：确保双方都准备好建立连接并能处理数据交换，避免资源浪费。
- **防止旧连接的影响**：如果某个连接已经关闭，三次握手可以确保不会误操作仍然未清除的旧连接。