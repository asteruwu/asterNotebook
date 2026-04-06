# Blocking I/O

![TCP_IP.dio-BIO.drawio](../dio图表/SRE/TCP_IP.dio-BIO.drawio.svg)

- **流程**：
  1. 用户线程调用 `recvfrom( )` 等待数据。
  2. 内核等待数据到达（如网卡接收数据）。
  3. 数据到达后，内核拷贝数据到用户空间。
  4. 用户线程解除阻塞，处理数据。



# Non-Blocking I/O

![TCP_IP.dio-NIO.drawio](../dio图表/SRE/TCP_IP.dio-NIO.drawio.svg)

- **流程**：
  1. 用户线程调用 `recvfrom( )`，若数据未就绪，内核立即返回 `EWOULDBLOCK`。
  2. 线程不断轮询检查数据是否就绪（忙等待）。
  3. 数据就绪后，拷贝到用户空间。



# I/O Multiplexing多路复用

![TCP_IP.dio-Multiplexing.drawio](../dio图表/SRE/TCP_IP.dio-Multiplexing.drawio.svg)

- **核心**：通过 `select`/`poll`/`epoll` 监听多个 I/O 事件，一个线程可以处理多个I/O操作。
- **流程**： 
  1. 用户线程调用 `epoll( )` 阻塞等待任一文件描述符就绪。
  2. 内核通知某个描述符可读/写。
  3. 用户线程调用 `recvfrom( )` 读取数据。

# 异步I/O
