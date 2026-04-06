官方教程文档：[Docker 教程](https://docs.docker.com/)

镜像下载网站(轩辕镜像)：[轩辕镜像个人专业版](https://xuanyuan.cloud/)

# 帮助命令

```shell
docker version #显示docker的版本信息
docker info    #显示docker的系统信息，包括镜像与容器的数量
docker --help  #查看所有docker指令以及描述
```

# 镜像命令

## docker images

查看所有镜像.

```shell
REPOSITORY                              TAG          IMAGE ID       CREATED       SIZE
docker.xuanyuan.run/library/mysql       latest       245a6c909dc0   2 weeks ago   921MB
docker.xuanyuan.run/library/wordpress   latest       25f690fa7ac7   3 weeks ago   703MB

#解释
REPOSITORY #镜像的仓库源
TAG        #镜像的标签
IMAGE ID   #镜像的ID
CREATED    #镜像的创建时间
SIZE       #镜像的大小

#可选项
	-a, --all    #列出所有镜像
	-q, --quiet  #只列出镜像id
```

## docker rmi

删除镜像.

```shell
#可选项
	-f	                      #删除指定的镜像，后接镜像id；若要输入多个id，则使用空格隔开
	-f $(docker images -aq)   #批量全部删除(嵌套命令)
```

# 容器命令

有了镜像才可创建容器，此处使用centos镜像为示例.

## docker run

创建并运行容器.

```shell
docker run [可选参数] [镜像名] [控制台]

#参数说明
--name='Name'  #容器名字，用来区分容器
-d             #后台运行
-it            #交互模式运行，能够进入容器查看相关内容
-p             #指定容器的端口
	-p ip:主机端口:容器端口
	-p 主机端口:容器端口（常用）
	-p 容器端口
	容器端口
-P             #随机指定端口（大p）

#启动并进入容器
$ docker run -it eeb6ee3f44bd /bin/bash  #使用交互模式运行，填写镜像id，使用bash命令（取决于控制台）
[root@92dc80c11d23 /]#
#↑注意到此处主机名已变为容器名

#在容器内部查看centos镜像
[root@4cdb47604525 /]# ls
anaconda-post.log  bin  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
```

## docker ps

查看容器.

```shell
#列出当前正在运行中的容器
docker ps

#列出当前正在运行的+运行过的容器
docker ps -a
CONTAINER ID   IMAGE          COMMAND   CREATED          STATUS                     PORTS     NAMES
4cdb47604525   eeb6ee3f44bd   "bash"    7 minutes ago    Exited (0) 3 minutes ago             wizardly_murdock
92dc80c11d23   eeb6ee3f44bd   "bash"    13 minutes ago   Up 13 minutes                        keen_jennings

#列出最近创建的容器
docker ps -a -n=?	#此处?填写个数

docker ps -a -n=1
CONTAINER ID   IMAGE          COMMAND   CREATED          STATUS                     PORTS     NAMES
4cdb47604525   eeb6ee3f44bd   "bash"    12 minutes ago   Exited (0) 8 minutes ago             wizardly_murdock

#只显示容器的编号
docker ps -q
92dc80c11d23
```

## exit

退出容器.

```shell
#退出容器并停止
[root@4cdb47604525 /]# exit
exit

#退出但不停止容器
快捷键ctrl + P + Q
[root@0094eae51097 /]#
86133@Dantalion MINGW64 ~
```

## docker rm

删除容器.

```shell
#删除指定容器
docker rm [容器id]

#删除所有容器
docker -f $(docker ps -aq)
```

> [!NOTE]
>
> 在运行中的容器不可被删除，若要强制删除只能使用`rm -f`
>
> `Error response from daemon: cannot remove container "0094eae51097": container is running: stop the container before removing or force remove`

## 启动和停止

```shell
docker start [容器id]     #启动容器
docker restart [容器id]   #重启容器
docker stop [容器id]      #停止当前正在运行的容器
docker kill [容器id]      #强制停止
```

# 其他常用命令

此处仍以镜像centos为例.

## docker run -d

后台启动容器.

```shell
docker run -d [容器名]

docker run -d eeb6ee3f44bd
d8247b1573f8641353f7eb684f0e591debfbc7c75d255a206d7e713432b59e23	#返回一个容器id
```

> [!CAUTION]
>
> 由于后台运行时要求必须要有前台进程；如果没有，则会在启动后自动停止运行，导致使用`docker ps`命令时显示该容器未在运行.

## docker logs

查看日志.

```shell
docker logs [容器id]
#可选项
-t	        #显示日志
-f          #显示时间戳
--tail n    #n表示日志条数
```

```shell
#创建容器并写入脚本
docker run -d sha256:eeb6ee3f44bd0b5103bb561b4c16bcb82328cfe5809ab675bb17ab3a16c517c9 /bin/bash -c "for i in{1..3}; do echo "Dantalion"; done"
a0adadbca1adf7d218694a2c643ee2d3d9bf0c30903447b900d87f1a51a0ddb9

#查看容器日志
docker logs -tf a0adadbca1adf7d218694a2c643ee2d3d9bf0c30903447b900d87f1a51a0ddb9
2025-08-11T04:06:41.478816740Z bash: -c: line 0: syntax error near unexpected token `in{1..3}'
2025-08-11T04:06:41.478849057Z bash: -c: line 0: `for i in{1..3}; do echo Dantalion; done'
```

## docker top

查看容器进程信息.

```shell
docker top [容器id]
```

## docker inspect

查看容器的元数据.

```shell
docker inspect [容器id]
```

## docker exec & docker attach

进入运行中的容器.

### docker exec

```shell
docker exec [可选参数] [容器id] [控制台]

docker exec -it a0adadbca1ad /bin/bash	#使用交互模式进入容器，控制台为bash
```

### docker attach

```shell
docker attach [容器id] [控制台]

docker attach a0adadbca1ad /bin/bash
```

> [!IMPORTANT]
>
> `exec`类似于开启一个新的终端，可以进行操作；
>
> `attach`则为直接进入正在运行的终端，不会产生新的进程.

## docker cp

从容器中拷贝文件到主机.

```shell
docker cp [容器文件地址] [主机地址]

#启动容器
docker start ca453d8cf3be
#进入容器并创建一个文件
    $ docker attach ca453d8cf3be
    #进入容器中的home文件夹
    [[root@ca453d8cf3be /]# cd /home
    #在home文件夹中创建一个新文件
    [root@ca453d8cf3be home]# touch dantalion.py
    #查看文件是否创建成功
    [root@ca453d8cf3be home]# ls
	dantalion.py
	#退出容器
	[root@ca453d8cf3be home]exit
	exit
#拷贝容器中的文件到主机
docker cp ca453d8cf3be:/home/dantalion.py /c/Users/86133
#查看主机中的文件，确认是否拷贝成功
ls
```

> [!NOTE]
>
> 即便容器停止运行，文件数据仍然存在，能够进行拷贝.
