# Part1. 基础必备

![Nginx-nginx处理请求流程图.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-nginx处理请求流程图.drawio.svg)

## Nginx架构与基本概念

**核心定位：**

- Nginx 是一个 **高性能 Web 服务器**、**反向代理服务器**，支持 **HTTP、HTTPS、邮件代理、TCP/UDP 转发**。
- 主要优势：高并发处理能力、低内存消耗、模块化、配置灵活。

**基本特点：**

- **轻量高效**：事件驱动（异步非阻塞）。
- **模块化**：核心 + 功能模块（HTTP、Stream、Mail）。
- **热加载**：修改配置后可平滑重启，不中断服务。
- **稳定可靠**：常用于大型网站的前端入口。

### master/worker 进程模型

**master 进程**

- 负责管理 worker（启动、重启、停止）。
- 接收信号（reload、quit）。
- **不直接处理请求**。

**worker 进程**

- 真正处理请求。
- 每个 worker **独立**，不共享连接。
- 数量通常 = CPU 核心数。

### 事件驱动机制

- **事件驱动**：worker 基于异步非阻塞 I/O 模型处理请求。
- 常用机制：
  - **Linux**：`epoll`（高效 I/O 多路复用）。
  - **BSD/OSX**：`kqueue`。
- 相比传统 `select/poll`，能同时处理成千上万连接，资源消耗低。

### 模块化架构

Nginx 的功能通过模块实现，主要分类：

- **核心模块**：基础配置、进程管理。
- **事件模块**：I/O 事件处理（epoll/kqueue）。
- **HTTP 模块**：HTTP 协议支持（代理、缓存、压缩）。
- **Stream 模块**：TCP/UDP 代理。
- **第三方模块**：如 Lua、GeoIP 等。

## 配置文件基础

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx配置.drawio.svg" alt="Nginx配置.drawio"  />

- **main**：进程数、日志路径等。

  ```nginx
  #user  nobody;
  worker_processes  1;
  
  #error_log  logs/error.log;
  #error_log  logs/error.log  notice;
  #error_log  logs/error.log  info;
  
  #pid        logs/nginx.pid;
  ```

- **events**：连接数、I/O 模型。

  ```nginx
  events {
      worker_connections  1024;
  }
  ```

- **http**：HTTP 服务配置。

  ```nginx
  http {
      include       mime.types;
      default_type  application/octet-stream;
      
      #以下内容在实际应用时应去掉注释，意味着访问记录（使用main格式）会输出到/logs/access.log中
      #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
      #                  '$status $body_bytes_sent "$http_referer" '
      #                  '"$http_user_agent" "$http_x_forwarded_for"';
  
      #access_log  logs/access.log  main;
  
      #启用高效的文件传输机制，不需要Nginx（用户态）的参与，数据直接从page cache拷贝到socket，再通过网卡发到客户端
      sendfile        on;
      #tcp_nopush     on;
  
      #设置客户端与服务器之间长连接的超时时间；一个合理的超时时间可以大幅减少TCP连接的建立和销毁开销，提升性能
      #keepalive_timeout  0;
      keepalive_timeout  65;
  
      #设置Gzip压缩，会在Nginx把响应转发给客户端之前对文本内容进行压缩（html、css等）加快传输速度
      #gzip  on;
  ```

- **server**：虚拟主机（域名/端口）。

  ```nginx
  server {
          listen       80;
          server_name  localhost;
      	...
  ```

- **location**：URL 路径匹配与处理规则。

  ```nginx
  location / {
              root   html;
              index  index.html index.htm;
          }
  ```

###  静态资源服务配置

**基本指令**

- `root`：指定资源根目录。
- `index`：默认首页文件。

```nginx
location / {
            root   html;
            index  index.html index.htm;
        }

error_page   500 502 503 504  /50x.html;
location = /50x.html {
            root   html;
        }
```

> [!NOTE]
>
> `/`：**默认配置**，用于返回静态资源；同时也是匹配网站的根路径，任何路径都会优先匹配；
>
> `error_page   500 502 503 504  /50x.html;`：表示当服务器返回 **500、502、503、504 错误**时，不直接把“丑陋的错误提示”给用户，而是**统一跳转**到 `/50x.html` 这个页面；
>
> `/50x.html`：**精确匹配**，只有请求完全符合此路径时才会调用这一规则，从root目录下查找文件返回错误页面。

### 日志配置

- `access_log`：访问日志

```nginx
#access_log  logs/access.log  main;
```

- `error_log`：错误日志

```nginx
#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;
```

- 自定义日志格式

```nginx
log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                  '$status $body_bytes_sent "$http_referer" '
                  '"$http_user_agent" "$http_x_forwarded_for"';
```

## 反向代理与负载均衡

### 反向代理

<img src="C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-反向代理.drawio.svg" alt="Nginx-反向代理.drawio"  />

- **`porxy_pass`：**把用户请求转发给后端服务器。

```nginx
location /api/ {									#匹配以api开头的路径，专门处理API请求
    proxy_pass http://backend_app;					#把请求转发给后端应用backend_app
    proxy_set_header Host $host;					#设置请求头为客户端的主机名
    proxy_set_header X-Real-IP $remote_addr;		#设置X-Real-IP头，把用户真实IP传给后端服务器
}
```

### 负载均衡

- **负载均衡算法**

  - **轮询（round robin）**（默认）
     顺序分配请求。

  ![Nginx-负载均衡_轮询.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-负载均衡_轮询.drawio.svg)

  - **最少连接（least_conn）**
     新请求分给连接数最少的服务器。

  ![Nginx-负载均衡_least_conn.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-负载均衡_least_conn.drawio.svg)

  - **IP 哈希（ip_hash）**
     根据客户端 IP 分配，保证会话粘性。

  ![Nginx-负载均衡_ip_hash.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-负载均衡_ip_hash.drawio.svg)

- **`upstream{}`：**定义后端服务器池。

```nginx
upstream backend_app {
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
}
```

# Part2. SRE重点

## 性能与稳定性调优

### sendfile

- 核心是 **page cache → socket → TCP/IP → 网卡**，跳过用户态(Nginx)缓冲。
- 提升 CPU 利用率和吞吐量。

**对比：**

![Nginx-sendfile对比.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-sendfile对比.drawio.svg)



### keepalive_timeout

- 减少 TCP 三次握手开销，复用 TCP 连接服务多个请求。
- 适合高并发场景。

### epoll/kqueue

- Nginx 的事件循环模型，避免线程/进程阻塞，每个 worker 可管理成千上万连接。
- 沿用IO模型中的多路复用。

![Nginx-epoll.drawio](C:\Users\86133\Desktop\学习\dio图表\SRE\Nginx-epoll.drawio.svg)
