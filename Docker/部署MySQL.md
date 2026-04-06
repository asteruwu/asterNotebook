# 创建容器

设置挂载.

```shell
dantalion@Dantalion:/$ docker run -d -p 3310:3306 -v /home/mysql/conf:/etc/mysql/conf.d:rw -v /home/mysql/data:/var/lib/mysql:rw -e MYSQL_ROOT_PASSWORD=
123456 --name mysql01 245a6c909dc0
c0c18f5bbf957368fe2aeee47d6190e4605228b0b31f99251b632d779bcc7d5a

#参数说明
-d		#后台运行
-p		#设置端口暴露
-v		#绑定主机目录和容器目录，建立映射关系
-e		#环境配置，特定的镜像需要
--name	#设置镜像名
```

# 建立连接

进入MySQL，建立新的连接：

![image-20250812165412601](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250812165412601.png)

将端口设置为创建容器时暴露的端口，密码也是创建容器时设置的密码.

# 测试

在MySQL中创建新的数据库.（此处为test）

![image-20250812165538954](C:\Users\86133\AppData\Roaming\Typora\typora-user-images\image-20250812165538954.png)

在主机目录中查看：

```shell
#访问主机下的home/mysql/data目录并列出其中的文件
dantalion@Dantalion:/home/mysql/data$ ls
'#ib_16384_0.dblwr'   client-cert.pem         private_key.pem
'#ib_16384_1.dblwr'   client-key.pem          public_key.pem
'#innodb_redo'        ib_buffer_pool          server-cert.pem
'#innodb_temp'        ibdata1                 server-key.pem
 auto.cnf             ibtmp1                  sys
 binlog.000001        mysql                   test
 binlog.000002        mysql.ibd               undo_001
 binlog.index         mysql.sock              undo_002
 ca-key.pem           mysql_upgrade_history
 ca.pem               performance_schema
 
 #注意到出现了新的文件test，说明同步成功
```