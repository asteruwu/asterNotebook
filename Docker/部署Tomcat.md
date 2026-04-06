# 创建容器

```shell
docker run -d -p 3355:8080 --name tomcat01 dcae2ebef501
42d513ec66d64548c70e77a1faedcbbaad4dffe98d42aa18f79abe0d2f06970f
#解释
-d		#后台运行
-p		#设置端口暴露，tomcat的默认内部端口为8080
--name	#设置容器名
```

# 进入容器

```shell
docker exec -it tomcat01 /bin/bash
root@42d513ec66d6:/usr/local/tomcat#

#解释
-it		#交互模式运行
\bash	#控制器为bash
```

# 测试容器

```shell
#访问容器文件夹下的所有目录
root@42d513ec66d6:/usr/local/tomcat# ls
bin  BUILDING.txt  conf  CONTRIBUTING.md  filtered-KEYS  lib  LICENSE  logs  native-jni-lib  NOTICE  README.md  RELEASE-NOTES  RUNNING.txt  temp  upstream-KEYS  webapps  webapps.dist  work

#显示详细目录
root@42d513ec66d6:/usr/local/tomcat# ls -al
total 240
drwxr-xr-x 1 root root  4096 Aug  7 17:16 .
drwxr-xr-x 1 root root  4096 Aug  7 17:16 ..
drwxr-xr-x 2 root root  4096 Aug  7 17:16 bin
-rw-r--r-- 1 root root 24262 Jul 31 16:29 BUILDING.txt
drwxr-xr-x 1 root root  4096 Aug 11 09:21 conf
-rw-r--r-- 1 root root  6166 Jul 31 16:29 CONTRIBUTING.md
-rw-r--r-- 1 root root 30936 Aug  7 17:16 filtered-KEYS
drwxr-xr-x 2 root root  4096 Aug  7 17:16 lib
-rw-r--r-- 1 root root 60517 Jul 31 16:29 LICENSE
drwxrwxrwt 1 root root  4096 Aug 11 09:21 logs
drwxr-xr-x 2 root root  4096 Aug  7 17:16 native-jni-lib
-rw-r--r-- 1 root root  2333 Jul 31 16:29 NOTICE
-rw-r--r-- 1 root root  3291 Jul 31 16:29 README.md
-rw-r--r-- 1 root root  6470 Jul 31 16:29 RELEASE-NOTES
-rw-r--r-- 1 root root 16109 Jul 31 16:29 RUNNING.txt
drwxrwxrwt 2 root root  4096 Aug  7 17:16 temp
-rw-r--r-- 1 root root 32010 Aug  7 17:16 upstream-KEYS
drwxr-xr-x 2 root root  4096 Aug  7 17:16 webapps
drwxr-xr-x 7 root root  4096 Jul 31 16:29 webapps.dist
drwxrwxrwt 2 root root  4096 Jul 31 16:29 work
```

# *解决无法访问网站的问题

将tomcat目录下webapps.dist中的文件复制粘贴到webapps.

```shell
root@42d513ec66d6:/usr/local/tomcat# cp -r webapps.dist/* webapps
#解释
-r					#递归复制粘贴
webapps.dist/*		 #选中该文件夹下的所有目录
```

> [!NOTE]
>
> 如果两个文件夹都在同一目录下，那么直接写文件夹名即可.

```shell
#访问网站测试
$ curl localhost:3355



<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <title>Apache Tomcat/11.0.10</title>
        <link href="favicon.ico" rel="icon" type="image/x-icon" />
        <link href="tomcat.css" rel="stylesheet" type="text/css" />
    </head>

    <body>
    ...
    </body>

</html>
```

[Tomcat](localhost:3355)

![image-20250811175636926](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250811175636926.png)
