> [!IMPORTANT]
>
> 用来构建docker镜像，本质上是一段命令脚本.

Dockerfile 是一个简单的文本文件，包含了一系列用户可以在命令行调用以组装镜像的命令。它的优势主要体现在以下几个方面：

- **自动化与可重复性 (Automation & Reproducibility)**
  - **一次编写，到处运行：** Dockerfile 明确定义了应用运行所需的所有环境（OS、库、依赖）。无论是在开发者的 MacBook、测试服务器还是生产环境的云主机上，构建出的镜像行为都是一致的。
  - **消除“环境配置漂移”：** 彻底解决了“在我的机器上能跑，在你那里跑不起来”的经典问题。
- **版本控制友好 (Version Control Integration)**
  - **代码化管理：** 作为一个纯文本文件，Dockerfile 可以像源代码一样提交到 Git 仓库中。这意味着环境配置的每一次变更都有记录（谁修改的、修改了什么、什么时候修改的），便于回滚和审查。
- **构建效率与性能 (Efficiency & Caching)**
  - **分层构建与缓存：** Docker 在构建时会利用分层缓存机制。如果你只修改了代码而没有修改依赖库，Docker 只会重新构建代码层，而复用之前的底层镜像。这极大地加快了构建速度。
  - **轻量级：** 相比于传递几十 GB 的虚拟机镜像文件，分享一个只有几 KB 的 Dockerfile 极其高效。
- **透明性与安全性 (Transparency & Security)**
  - **清晰的审计：**任何人打开 Dockerfile 都能清楚地看到镜像里安装了什么软件、开放了什么端口、运行了什么命令。这比黑盒式的二进制文件或预装 VM 镜像更安全、更透明。

| **特性**       | **传统虚拟机/手动部署**         | **Dockerfile / 容器化**        |
| -------------- | ------------------------------- | ------------------------------ |
| **交付物**     | 部署文档、安装手册、VM 镜像     | Dockerfile 及其构建出的镜像    |
| **环境一致性** | 低（依赖人工操作，容易出错）    | **极高**（代码定义，机器执行） |
| **启动速度**   | 分钟级                          | **秒级**                       |
| **资源利用率** | 低（通过 VM 隔离，Overhead 大） | **高**（共享内核，进程级隔离） |
| **更新方式**   | 在线修补（Mutable）             | **整体替换（Immutable）**      |

# 构建步骤

> 1.编写一个dockerfile文件
>
> 2.`docker build`构建成为一个镜像
>
> 3.`docker run`运行镜像，构建容器
>
> *4.`docker push`发布镜像-->Docker Hub

# 详细过程

## 基础语法

- 每个关键字（指令）必须都是大写字母
- 按照从上到下的顺序依次执行
- `#`表示注释
- 每个指令都会创建一个新的镜像层并提交

## dockerfile命令

```dockerfile
FROM			#基础镜像
MAINTAINER		#维护者信息；镜像作者（一般留下姓名+邮箱）
RUN				#镜像构建的时候需要运行的命令
ADD				#自行添加压缩内容
WORKDIR			#镜像的默认工作目录
VOLUME			#挂载的目录
EXPOSE			#指定暴露端口
CMD				#指定容器启动的时候要运行的命令，只有最后一个会生效，且可被替代
ENTRYPOINT		#指定容器启动的时候要运行的命令，且可追加
COPY			#类似ADD，将文件拷贝到镜像中
ENV				#构建时设置环境变量
```

## 测试--构建自己的rockylinux镜像

> [!TIP]
>
> Docker Hub中的镜像基本都是从`FROM scratch`开始.

### 查看官方rockylinux镜像

```shell
#创建容器并运行
dantalion@Dantalion:/$ docker run -it --name rockylinux01 dfaa211c6b30 /bin/bash

#查看当前正在运行的容器
bash-5.1# dantalion@Dantalion:/$ docker ps
CONTAINER ID   IMAGE          COMMAND       CREATED          STATUS          PORTS     NAMES
c29e3f440d94   dfaa211c6b30   "/bin/bash"   25 seconds ago   Up 24 seconds             rockylinux01

#以交互模式进入容器
dantalion@Dantalion:/$ docker exec -it rockylinux01 /bin/bash

#查看当前目录以及目录下的所有文件
bash-5.1# pwd
/
bash-5.1# ls
afs  bin  dev  etc  home  lib  lib64  lost+found  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var

#指令测试
bash-5.1# vim test
bash: vim: command not found
bash-5.1# ifconfig
bash: ifconfig: command not found
```

> [!CAUTION]
>
> 注意到官方源镜像是被压缩过的，命令并不完整；因此需要进行额外下载，完善命令，完善后的镜像可保存为自己的镜像.

### 书写dockerfile

目的：增加`vim`命令和`net-tools`相关命令.

```shell
#主机终端
#到达存储dockerfile的目录，使用vim命令进行编辑
dantalion@Dantalion:/home$ ls
dantalion  dockerfile  mysql  test
dantalion@Dantalion:/home$ cd dockerfile
dantalion@Dantalion:/home/dockerfile$ vim mydockerfile
```

```dockerfile
#mydockerfile内部
FROM rockylinux:8							  #设置源镜像
MAINTAINER dantalion<2691974850@qq.com>			#设置作者和联系方式

ENV MYPATH=/usr/local						  #采用键值对的形式定义环境变量
WORKDIR $MYPATH								 #将环境变量赋给WORKDIR参数，设置为工作路径

RUN dnf -y install vim-enhanced				   #下载vim命令、net-tools相关网络命令、清除缓存
RUN dnf -y install net-tools
RUN dnf clean all

EXPOSE 80									#设置暴露端口

CMD echo $MYPATH							 #使用bash控制台
CMD echo "-----end-----"
CMD /bin/bash
```

### 构建镜像

```shell
#主机终端
dantalion@Dantalion:/home/dockerfile$ docker build -f mydockerfile -t mylinux:1.0 .
#解释
-f		#对应的dockerfile文件名
-t		#镜像名:版本
[+] Building 79.5s (10/10) FINISHED
```

> [!IMPORTANT]
>
> 不要忘记最后有一个(.)

### 测试镜像

```shell
#主机终端
@Dantalion:/$ docker run -it mylinux:1.0

#容器终端
#查看当前路径，应当与dockerfile中设置的工作路径一致
[root@e0aa281ea6bb local]# pwd
/usr/local

#测试网络命令
[root@e0aa281ea6bb local]# ifconfig
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether e2:49:72:77:8d:03  txqueuelen 0  (Ethernet)
        RX packets 12  bytes 1172 (1.1 KiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 3  bytes 126 (126.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        inet6 ::1  prefixlen 128  scopeid 0x10<host>
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

#测试vim命令（写入hello world！）
[root@e0aa281ea6bb local]# vim test
[root@e0aa281ea6bb local]# cat test
hello world!
```

# 查看镜像生成过程

使用`docker history`.

```shell
dantalion@Dantalion:/$ docker history 2cd1d97f893f
IMAGE          CREATED       CREATED BY                                      SIZE      COMMENT
2cd1d97f893f   4 weeks ago   CMD ["nginx" "-g" "daemon off;"]                0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   STOPSIGNAL SIGQUIT                              0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   EXPOSE map[80/tcp:{}]                           0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   ENTRYPOINT ["/docker-entrypoint.sh"]            0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   COPY 30-tune-worker-processes.sh /docker-ent…   4.62kB    buildkit.dockerfile.v0
<missing>      4 weeks ago   COPY 20-envsubst-on-templates.sh /docker-ent…   3.02kB    buildkit.dockerfile.v0
<missing>      4 weeks ago   COPY 15-local-resolvers.envsh /docker-entryp…   389B      buildkit.dockerfile.v0
<missing>      4 weeks ago   COPY 10-listen-on-ipv6-by-default.sh /docker…   2.12kB    buildkit.dockerfile.v0
<missing>      4 weeks ago   COPY docker-entrypoint.sh / # buildkit          1.62kB    buildkit.dockerfile.v0
<missing>      4 weeks ago   RUN /bin/sh -c set -x     && groupadd --syst…   117MB     buildkit.dockerfile.v0
<missing>      4 weeks ago   ENV DYNPKG_RELEASE=1~bookworm                   0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   ENV PKG_RELEASE=1~bookworm                      0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   ENV NJS_RELEASE=1~bookworm                      0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   ENV NJS_VERSION=0.9.0                           0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   ENV NGINX_VERSION=1.29.0                        0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   LABEL maintainer=NGINX Docker Maintainers <d…   0B        buildkit.dockerfile.v0
<missing>      4 weeks ago   # debian.sh --arch 'amd64' out/ 'bookworm' '…   74.8MB    debuerreotype 0.15
```

# CMD vs ENTRYPOINT

## CMD

基于rockylinux镜像，添加`CMD`命令，生成新镜像进行测试：

### 书写dockerfile

```shell
#主机终端
dantalion@Dantalion:/home/dockerfile$ vim cmd-test
dantalion@Dantalion:/home/dockerfile$ cat cmd-test
FROM docker.xuanyuan.run/library/rockylinux:9.3.20231119-minimal
CMD ["ls","-a"]
```

### 构建镜像

```shell
#主机终端
dantalion@Dantalion:/home/dockerfile$ docker build -f cmd-test -t ctest:1.0 .
[+] Building 0.0s (5/5) FINISHED
```

### 运行镜像

```shell
dantalion@Dantalion:/home/dockerfile$ docker run ctest:1.0
.
..
.dockerenv
afs
bin
dev
etc
home
lib
lib64
lost+found
media
mnt
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
```

> [!NOTE]
>
> 注意到这里运行镜像时直接执行了`CMD`命令，列举出了所有子目录.

### 命令测试

现尝试追加命令`-l`：

```shell
dantalion@Dantalion:/home/dockerfile$ docker run ctest:1.0 -l
docker: Error response from daemon: failed to create task for container: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: exec: "-l": executable file not found in $PATH: unknown

#因为dockerfile中的CMD命令可被替换，这里就被替换成了-l，而-l并不是一个命令，所以会报错；只有写入完整命令ls -al才可成功运行.
```

## ENTRYPOINT

基于rockylinux镜像，添加`ENTRYPOINT`命令，生成新镜像进行测试：

### 书写dockerfile

```shell
dantalion@Dantalion:/home/dockerfile$ vim entrypoint-test
dantalion@Dantalion:/home/dockerfile$ sudo vim entrypoint-test
dantalion@Dantalion:/home/dockerfile$ cat entrypoint-test
FROM rockylinux:8
ENTRYPOINT ["ls","-a"]
```

### 构建镜像

```shell
dantalion@Dantalion:/home/dockerfile$ docker build -f entrypoint-test -t etest:1.0 .
[+] Building 1.4s (5/5) FINISHED
```

### 运行镜像

```shell
dantalion@Dantalion:/home/dockerfile$ docker run etest:1.0
.
..
.dockerenv
bin
dev
etc
home
lib
lib64
lost+found
media
mnt
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
```

### 命令测试

```shell
dantalion@Dantalion:/home/dockerfile$ docker run etest:1.0 -l
total 56
drwxr-xr-x   1 root root 4096 Aug 13 06:32 .
drwxr-xr-x   1 root root 4096 Aug 13 06:32 ..
-rwxr-xr-x   1 root root    0 Aug 13 06:32 .dockerenv
lrwxrwxrwx   1 root root    7 Oct 11  2021 bin -> usr/bin
drwxr-xr-x   5 root root  340 Aug 13 06:32 dev
drwxr-xr-x   1 root root 4096 Aug 13 06:32 etc
drwxr-xr-x   2 root root 4096 Oct 11  2021 home
lrwxrwxrwx   1 root root    7 Oct 11  2021 lib -> usr/lib
lrwxrwxrwx   1 root root    9 Oct 11  2021 lib64 -> usr/lib64
drwx------   2 root root 4096 Nov 19  2023 lost+found
drwxr-xr-x   2 root root 4096 Oct 11  2021 media
drwxr-xr-x   2 root root 4096 Oct 11  2021 mnt
drwxr-xr-x   2 root root 4096 Oct 11  2021 opt
dr-xr-xr-x 362 root root    0 Aug 13 06:32 proc
dr-xr-x---   2 root root 4096 Nov 19  2023 root
drwxr-xr-x  12 root root 4096 Nov 19  2023 run
lrwxrwxrwx   1 root root    8 Oct 11  2021 sbin -> usr/sbin
drwxr-xr-x   2 root root 4096 Oct 11  2021 srv
dr-xr-xr-x  13 root root    0 Aug 13 06:32 sys
drwxrwxrwt   2 root root 4096 Nov 19  2023 tmp
drwxr-xr-x  12 root root 4096 Nov 19  2023 usr
drwxr-xr-x  19 root root 4096 Nov 19  2023 var

#-l可以直接追加在ENTRYPOINT的命令后
```

# 制作tomcat镜像

## 安装压缩包

![image-20250813160909566](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250813160909566.png)

地址：`/home/dantalion/tomcat`

## 书写dockerfile

```shell
dantalion@Dantalion:/$ cd home/dockerfile
dantalion@Dantalion:/home/dockerfile$ sudo vim tomcat
```

```dockerfile
FROM rockylinux:8
MAINTAINER dantalion<2691974850@qq.com>

ADD /home/dantalion/tomcat/jdk-24_linux-x64_bin.tar.gz /usr/local/
ADD /home/dantalion/tomcat/apache-tomcat-11.0.10.tar.gz /usr/local/

RUN yum -y install vim-enhanced && yum clean all

ENV MYPATH /usr/local
WORKDIR $MYPATH

ENV JAVA_HOME /usr/local/jdk-24.0.2
ENV CATALINA_HOME /usr/local/apache-tomcat-11.0.10
ENV CATALINA_BASE /usr/local/apache-tomcat-11.0.10
ENV PATH $CATALINA_HOME/bin:$JAVA_HOME/bin:$PATH

VOLUME /usr/local/apache-tomcat-11.0.10/webapps
VOLUME /usr/local/apache-tomcat-11.0.10/conf

EXPOSE 8080

CMD ["catalina.sh", "run"]
```

## 构建镜像并测试运行

```shell
dantalion@Dantalion:/$ docker build -f /home/dockerfile/tomcat -t mytomcat:1.0 .
[+] Building 1.8s (10/10) FINISHED

dantalion@Dantalion:/$ docker run mytomcat:1.0
13-Aug-2025 08:05:12.406 INFO [main] org.apache.catalina.startup.VersionLoggerListener.log Server version name:   Apache Tomcat/11.0.10
13-Aug-2025 08:05:12.408 INFO [main] org.apache.catalina.startup.VersionLoggerListener.log Server built:          Jul 31 2025 16:29:14 UTC
13-Aug-2025 08:05:12.408 INFO [main] org.apache.catalina.startup.VersionLoggerListener.log Server version number: 11.0.10.0
#能够输出日志说明运行成功
```

## 个人tomcat网页创建

### 运行容器，设置挂载

```shell
#创建容器并运行
dantalion@Dantalion:~/tomcat$ docker run -it -p 9090:8080 --name dantalionweb -v /home/dantalion/tomcat/WEB-INF:/usr/local/apache-tomcat-11.0.10/webapps/test:rw -v /home/dantalion/tomcat/logs:/usr/local/jdk-24.0.2/logs:rw mytomcat:1.0

#运行成功则输出日志
Using CATALINA_BASE:   /usr/local/apache-tomcat-11.0.10
Using CATALINA_HOME:   /usr/local/apache-tomcat-11.0.10
Using CATALINA_TMPDIR: /usr/local/apache-tomcat-11.0.10/temp
Using JRE_HOME:        /usr/local/jdk-24.0.2
Using CLASSPATH:       /usr/local/apache-tomcat-11.0.10/bin/bootstrap.jar:/usr/local/apache-tomcat-11.0.10/bin/tomcat-juli.jar
Using CATALINA_OPTS:
13-Aug-2025 09:49:02.740 INFO [main] org.apache.catalina.startup.VersionLoggerListener.log Server version name:   Apache Tomcat/11.0.10
```

> [!IMPORTANT]
>
> 1.此处`docker run`不能再最后写入`/bin/bash`，不然会覆盖镜像直接运行catalina.sh的命令，直接进入bash，而不是启动tomcat；
>
> 2.设置挂载的目录时，需要保证主机文件夹、本地jsp文件与容器中WEB-INF、web.xml的结构一致，如下图所示：web.xml在WEB-INF目录下时则jsp文件也需在主机WEB-INF下，若容器中二者同级别，在主机中也需保持同级别.

### 写入jsp文件

此处在容器外部（即主机中）书写，存储在WEB-INF目录下；由于设置有数据挂载，所以会自动同步到容器中的webapps/test目录下.

```shell
dantalion@Dantalion:~/tomcat/WEB-INF$ sudo vim index.jsp
dantalion@Dantalion:~/tomcat/WEB-INF$ cat index.jsp
<%@ page language="java" contentType="text/html; charset=ISO-8859-1" pageEncoding="ISO-8859-1"%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome Page</title>
</head>
<body>
    <h1>Welcome to the JSP Example</h1>

    <!-- Check if a user name is passed -->
    <%
        String userName = request.getParameter("name");
        if (userName != null && !userName.isEmpty()) {
            out.println("<h2>Hello, " + userName + "!</h2>");
        } else {
            out.println("<h2>Please enter your name below:</h2>");
        }
    %>

    <!-- Form to accept user's name -->
    <form action="" method="get">
        <label for="name">Your Name: </label>
        <input type="text" id="name" name="name" required>
        <input type="submit" value="Submit">
    </form>

</body>
</html>
```

> [!NOTE]
>
> 写这个文件是前端的知识，无需在意

### 检查文件是否同步成功

```shell
#进入容器中进行挂载了的目录
dantalion@Dantalion:~/tomcat/WEB-INF$ docker exec -it 4d4a98ca3ae1 /bin/bash
[root@4d4a98ca3ae1 local]# ls
apache-tomcat-11.0.10  bin  etc  games  include  jdk-24.0.2  lib  lib64  libexec  sbin  share  src
[root@4d4a98ca3ae1 local]# cd apache-tomcat-11.0.10/webapps/test

#查看子目录以及文件（同步成功）
[root@4d4a98ca3ae1 test]# ls
index.jsp
```

### 访问网站

https://localhost:9090/test

![image-20250813182657640](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250813182657640.png)

### 访问路径问题补充

> #### tomcat的默认部署结构：
>
> webapps目录下的每个子文件夹都会被当作一个独立的web应用.

直接使用localhost:9090会指向webapps下的ROOT应用，即webapps/ROOT.

#### URL组成规则

http://主机:端口/上下文路径/资源路径

所以有：

- **主机：**`localhost`
- **端口：**`9090`(映射到容器内部的8080)
- **上下文路径：**`/test`(来自文件夹名)
- **资源路径：**你的JSP文件名(如果访问的是index.jsp可以省略)

#### 正确访问方式

- 如果文件是**`test/index.jsp`：**`http://localhost:9090/test/`
- 如果文件是**`test/hello.jsp`：**`http://localhost:9090/test/hello.jsp`

## 获得tomcat网站访问权限

> [!IMPORTANT]
>
> 注意，此处要修改的文件必须确保已经设置了挂载，否则重启容器后修改的信息就会被抹除。

### 创建用户

文件位置：`/usr/local/apache-tomcat-11.0.10/conf/tomcat-users.xml`

```bash
#进入容器
dantalion@Dantalion:/$ docker exec -it mytomcat bash

#抵达用户文件所在的目录并修改
[root@5aa1cb3ee4b9 local]# ls
apache-tomcat-11.0.10  bin  etc  games  include  jdk-24.0.2  lib  lib64  libexec  sbin  share  src
[root@5aa1cb3ee4b9 local]# cd apache-tomcat-11.0.10/conf
[root@5aa1cb3ee4b9 conf]# ls
Catalina             context.xml           jaspic-providers.xsd  server.xml        tomcat-users.xsd
catalina.properties  jaspic-providers.xml  logging.properties    tomcat-users.xml  web.xml
[root@5aa1cb3ee4b9 conf]# vim tomcat-users.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- ...

  Built-in Tomcat manager roles:
    - manager-gui    - allows access to the HTML GUI and the status pages
    - manager-script - allows access to the HTTP API and the status pages
    - manager-jmx    - allows access to the JMX proxy and the status pages
    - manager-status - allows access to the status pages only

  ...
-->
<!--
  The sample user and role entries below are intended for use with the
  examples web application. They are wrapped in a comment and thus are ignored
  when reading this file. If you wish to configure these users for use with the
  examples web application, do not forget to remove the <!.. ..> that surrounds
  them. You will also need to set the passwords to something appropriate.
-->
<!--
  <role rolename="tomcat"/>
  <role rolename="role1"/>
  <user username="tomcat" password="<must-be-changed>" roles="tomcat"/>
  <user username="both" password="<must-be-changed>" roles="tomcat,role1"/>
  <user username="role1" password="<must-be-changed>" roles="role1"/>
-->

  <role rolename="tomcat"/>
  <role rolename="role1"/>
  <role rolename="manager-gui"/>
  <role rolename="manager-script"/>
  <role rolename="manager-jmx"/>
  <role rolename="manager-status"/>
  <user username="dantalion" password="dantalion" roles="manager-gui,manager-script,manager-jmx,manager-status"/>


</tomcat-users>
```

> 重点在于添加管理员以及用户，设置用户名称和密码，并给它授权。

### 授权远程访问

文件位置：`/usr/local/apache-tomcat-11.0.10/webapps/manager/META-INF/context.xml`

```bash
[root@5aa1cb3ee4b9 local]# cd apache-tomcat-11.0.10
[root@5aa1cb3ee4b9 apache-tomcat-11.0.10]# ls
BUILDING.txt  CONTRIBUTING.md  LICENSE  NOTICE  README.md  RELEASE-NOTES  RUNNING.txt  bin  conf  lib  logs  temp  webapps  work
[root@5aa1cb3ee4b9 apache-tomcat-11.0.10]# cd webapps
[root@5aa1cb3ee4b9 webapps]# ls
ROOT  docs  examples  host-manager  manager
[root@5aa1cb3ee4b9 webapps]# cd manager
[root@5aa1cb3ee4b9 manager]# ls
META-INF  WEB-INF  css  images  index.jsp  status.xsd  xform.xsl
[root@5aa1cb3ee4b9 manager]# cd META-INF
[root@5aa1cb3ee4b9 META-INF]# ls
context.xml
[root@5aa1cb3ee4b9 META-INF]# vim context.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
...
-->
<Context antiResourceLocking="false" privileged="true" ignoreAnnotations="true">
  <CookieProcessor className="org.apache.tomcat.util.http.Rfc6265CookieProcessor"
                   sameSiteCookies="strict" />

  <!--
  <Valve className="org.apache.catalina.valves.RemoteAddrValve"
         allow="127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />
  -->
  <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
```

> 重点在于把` <Valve className="org.apache.catalina.valves.RemoteAddrValve"` 
>
> ​			`allow="127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />`写作注释。

# 发布镜像（阿里云）

此前已注册阿里云账号，并且创建了命名空间dantalion/镜像仓库dantalion_repository.

## 登录阿里云账号

```shell
$ docker login --username=dantalion0511 crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com
```

## 标记本地镜像

```shell
$ docker images
REPOSITORY                                                                                  TAG                    IMAGE ID       CREATED         SIZE
mytomcat                                                                                    1.0                    14fceac2d78c   22 hours ago    677MB
```

```shell
$ docker tag [ImageId] crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com/dantalion/dantalion_repository:[镜像版本号]

$ docker tag 14fceac2d78c crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com/dantalion/dantalion_repository:latest
```

## 推送到registry

```shell
$ docker images
REPOSITORY                                                                                  TAG                    IMAGE ID       CREATED         SIZE
crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com/dantalion/dantalion_repository   latest                 14fceac2d78c   22 hours ago    677MB
```

```shell
$ docker push crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com/dantalion/dantalion_repository:latest
The push refers to repository [crpi-6uqp9ssq163g5u6e.cn-shenzhen.personal.cr.aliyuncs.com/dantalion/dantalion_repository]
5f70bf18a086: Pushed
a6b6152c03f7: Pushing [====================>                              ]   15.8MB/38.35MB
cedf5d9b95ed: Pushing [========>                                          ]  3.401MB/18.91MB
f2d56380bfad: Pushing [>                                                  ]  6.093MB/422.5MB
c1827ee010db: Pushing [=>                                                 ]  5.499MB/197.6MB
```

> [!NOTE]
>
> 注意到即便是`push`镜像，也是按层上传.

上传成功后可在阿里云账号中查看：

![image-20250814135140171](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250814135140171.png)

![image-20250814135228746](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250814135228746.png)

以及相关的镜像层信息：

![image-20250814135305190](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250814135305190.png)
