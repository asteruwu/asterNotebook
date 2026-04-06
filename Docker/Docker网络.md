# Docker 网络模型

Docker 提供了几种不同的网络驱动（Network Drivers），每种驱动都有不同的用途和场景：

- **Bridge 网络**：默认的网络驱动，适用于在单个主机上运行的容器。容器通过虚拟网桥（`docker0`）与主机进行通信.
- **Host 网络**：容器与宿主机共享网络接口，适合对性能要求较高且不需要容器隔离的场景.
- **None 网络**：容器没有网络连接，适用于需要完全隔离的环境.
- **Overlay 网络**：用于跨多台主机的容器通信，适用于 Docker Swarm 或 Kubernetes 集群中.
- **Macvlan 网络**：允许容器直接拥有独立的 IP 地址，适合要求容器与宿主机网络完全隔离的场景.

# 重要特性

- **实现容器间的通信：**同一网络中的容器可以通过容器名互相通信(Docker内置DNS)，不同网络中的容器默认不能直接通信.
- **端口映射：**主机端口:容器端口

# 常用命令

## 网络

```shell
#列出所有网络
dantalion@Dantalion:~$ docker network ls
NETWORK ID     NAME      DRIVER    SCOPE
49efd3884324   bridge    bridge    local
00d545e52210   host      host      local
75e0b6f0298c   none      null      local

#创建自定义网络并查看
dantalion@Dantalion:~$ docker network create my-network
f71f10c3afaffe136b181eaea36a1440b4a455d93805e0cfd4f5fb6c7e35bea0
dantalion@Dantalion:~$ docker network ls
NETWORK ID     NAME         DRIVER    SCOPE
f71f10c3afaf   my-network   bridge    local

#查看网络详细信息
dantalion@Dantalion:~$ docker network inspect f71f10c3afaf
[
    {
        "Name": "my-network",
        "Id": "f71f10c3afaffe136b181eaea36a1440b4a455d93805e0cfd4f5fb6c7e35bea0",
        "Created": "2025-08-14T07:52:31.059283033Z",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv4": true,
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "172.18.0.0/16",
                    "Gateway": "172.18.0.1"
                }
            ]
        },
        "Internal": false,
        "Attachable": false,
        "Ingress": false,
        "ConfigFrom": {
            "Network": ""
        },
        "ConfigOnly": false,
        "Containers": {},
        "Options": {
            "com.docker.network.enable_ipv4": "true",
            "com.docker.network.enable_ipv6": "false"
        },
        "Labels": {}
    }
]

#删除网络
dantalion@Dantalion:~$ docker network rm my-network
```

## 网络+容器

```shell
#运行容器并连接到指定网络（可以发现网络已设置为my-network）
dantalion@Dantalion:~$ docker run -it --network my-network ad5708199ec7
dantalion@Dantalion:~$ docker inspect 5e3095bc8ad5
 "Networks": {
                "my-network": {
                    "IPAMConfig": null,
                    "Links": null,
                    "Aliases": null,
                    "MacAddress": "4a:2a:f3:64:ac:6d",
                    "DriverOpts": null,
                    "GwPriority": 0,
                    "NetworkID": "f71f10c3afaffe136b181eaea36a1440b4a455d93805e0cfd4f5fb6c7e35bea0",
                    "EndpointID": "e74af39abf040153abc2e8bff758767415cf944e9c2757b976095c399326d17f",
                    "Gateway": "172.18.0.1",
                    "IPAddress": "172.18.0.2",
                    "IPPrefixLen": 16,
                    "IPv6Gateway": "",
                    "GlobalIPv6Address": "",
                    "GlobalIPv6PrefixLen": 0,
                    "DNSNames": [
                        "frosty_shirley",
                        "5e3095bc8ad5"
                    ]
                }
            }
            
#将运行中的容器连接到网络
dantalion@Dantalion:~$ docker network connect my-net01 5e3095bc8ad5
dantalion@Dantalion:~$ docker inspect 5e3095bc8ad5
"Networks": {
                "my-net01": {
                    "IPAMConfig": {},
                    "Links": null,
                    "Aliases": [],
                    "MacAddress": "c6:dd:dd:90:4e:f4",
                    "DriverOpts": {},
                    "GwPriority": 0,
                    "NetworkID": "9784321fea29674607d2713f6439094e8638a28be0cf769b66c4090763b04c8e",
                    "EndpointID": "1a48a537535e320fc1dfb99ae3ee5598f7eb30ae60591045cf6ef2fafa150f95",
                    "Gateway": "172.19.0.1",
                    "IPAddress": "172.19.0.2",
                    "IPPrefixLen": 16,
                    "IPv6Gateway": "",
                    "GlobalIPv6Address": "",
                    "GlobalIPv6PrefixLen": 0,
                    "DNSNames": [
                        "frosty_shirley",
                        "5e3095bc8ad5"
                    ]
                },
                
#断开容器与网络的连接
dantalion@Dantalion:~$ docker network disconnect my-network 5e3095bc8ad5
```



