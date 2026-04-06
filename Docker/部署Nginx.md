# 创建容器

```shell
docker run -d --name nginx01 -p 3344:80 2cd1d97f893f
a622a73b3627e0df232a88f0c4857a6196e7dd941284e884904f0561b27e4f4a

#解释
-d		            #后台运行
--name nginx01		#将容器名设置为nginx01
-p 3344:80		    #端口暴露，由宿主机linux端口到nginx容器内部端口；宿主机端口可以任意指定
```

# 进入容器

```shell
docker exec -it nginx01 /bin/bash
#解释
-exec	#在新的终端中进入容器
-it		#使用交互模式
\bash	#使用bash控制台

$ docker exec -it nginx01 \bash
root@a622a73b3627:/#
```

# 测试容器

```shell
#网站访问测试
$ curl localhost:3344	#curl是一个常用的命令行工具，用于通过网络发送 HTTP 请求并接收响应。它通常用于测试和调试网络服务
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
#说明测试通过

root@a622a73b3627:/# whereis nginx	#查找nginx的位置
nginx: /usr/sbin/nginx /usr/lib/nginx /etc/nginx /usr/share/nginx

root@a622a73b3627:/# cd /etc/nginx	#进入相应nginx文件位置
root@a622a73b3627:/etc/nginx# ls	#查看目录下包含的文件
conf.d  fastcgi_params  mime.types  modules  nginx.conf  scgi_params  uwsgi_params
```

[Nginx](localhost:3344)

![image-20250811180110156](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250811180110156.png)