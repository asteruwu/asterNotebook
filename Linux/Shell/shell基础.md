# 基本操作

## 解释器

- `#!/bin/bash`表示使用bash解释器
- `#!/usr/bin/python3.12`表示使用python解释器
- `#!env [变量名]`表示使用环境变量所定义的解释器

> [!TIP]
>
> 如果未在脚本中指定，则默认的解释器为当前的shell；可以用`echo $SHELL`进行查看当前解释器。

```bash
dantalion@Dantalion:~$ echo $SHELL
/bin/bash
```

## 执行

- **授权：**`chmod +x [文件路径]`
- **直接运行：**`./[文件路径]`

## 示例

此处以py文件为例。

### 书写py脚本

```bash
#! /usr/bin/python3.12
# coding:utf-8

print("你好世界\nhelloworld")
```

### 授权运行

```bash
#授权
dantalion@Dantalion:~/shell$ chmod +x test.py

#运行
dantalion@Dantalion:~/shell$ ./test.py
你好世界
helloworld
```

# 变量

## 变量定义与赋值

- 无需定义类型（shell为弱类型编程语言）。
- 变量名与值之间不得有空格。

## 变量引用

- 使用`$`引用变量。

  - ```bash
    dantalion@Dantalion:~/shell$ music="aster"
    dantalion@Dantalion:~/shell$ echo $music
    aster
    dantalion@Dantalion:~/shell$ echo ${music}#大括号可省略
    aster
    ```

- 将linux命令得到的结果赋值给变量：

  - ```bash
    #使用`命令`
    
    dantalion@Dantalion:~/shell$ name=`ls`
    dantalion@Dantalion:~/shell$ echo $name
    test.py test.sh
    ```

## 变量的作用域

- 使用`pstree`查看当前进程树（嵌套结构）。

  - ```bash
    systemd─┬─2*[agetty]
            ├─cron
            ├─dbus-daemon
            ├─init-systemd(Ub─┬─SessionLeader───Relay(877)───bash───pstree
    ```

- **本地变量：**针对shell进程定义。

- **环境变量：**又名全局变量，针对当前进程以及所有子进程。

- **局部变量：**针对shell函数或是shell脚本。

- **特殊变量：**如特殊参数变量以及特殊状态变量，后续笔记将进行详细解释。

- **父子shell：**

  - 每使用`bash`去执行一个.sh脚本，都会产生一个子shell。


  - 若执行方式不同，shell环境也会不同（`bash`和`source`）。


  - ![shell.dio.drawio](../../dio图表/SRE/shell.dio.drawio.svg)

  - `bash`会**启动一个子shell**，但执行脚本后则返回父shell进程，子shell的变量不会对父shell产生影响：

    ```bash
    dantalion@Dantalion:~/shell$ name="aster"
    dantalion@Dantalion:~/shell$ cat test.sh
    name="test"
    dantalion@Dantalion:~/shell$ bash test.sh
    dantalion@Dantalion:~/shell$ echo $name
    aster
    ```


  - `source`直接在当前shell（且**不产生子shell**）执行脚本，所有变量都会影响父shell：

    ```bash
    dantalion@Dantalion:~/shell$ source test.sh
    dantalion@Dantalion:~/shell$ echo $name
    test
    ```

  - 使用`pstree`或`ps -ef --forest`查看线程：

    ```bash
    dantalion@Dantalion:~/shell$ sh
    $ pstree
    init-systemd(Ub─┬─SessionLeader───Relay(755)───bash───sh───pstree
    
    $ ps -ef --forest
    root         753       2  0 12:33 ?        00:00:00  \_ /init
    root         754     753  0 12:33 ?        00:00:00      \_ /init
    dantali+     755     754  0 12:33 pts/2    00:00:00          \_ -bash
    dantali+    1118     755  0 15:53 pts/2    00:00:00              \_ sh
    dantali+    1121    1118  0 15:54 pts/2    00:00:00                  \_ ps -ef --forest
    ```

## 环境变量

环境变量一般是指通过`export`内置命令导出的变量，用于定义shell的运行环境，保证shell脚本的正确运行；

shell则根据设定好的环境变量确定登录的用户名、PATH路径、文件系统等各个应用。

### 查看环境变量

`export`，显示和设置环境变量值。

### 撤销环境变量	

`unset`，删除变量或函数。

### 设置只读变量

定义变量时添加关键字`readonly`。

```bash
dantalion@Dantalion:~$ readonly name="aster"
dantalion@Dantalion:~$ name="蛋挞"
-bash: name: readonly variable
```

## 特殊参数变量

```bash
$0		#获取shell脚本文件名以及脚本文件路径（位置参数）
$n		#获取脚本第n个参数（1-9），若大于9则需加上大括号，如${10}
$#		#获取执行的shell脚本下参数的总个数
$*		#获取shell脚本所有参数，不加引号的话与$@相同，"$*"则会额外将所有参数提取为单个字符串
$@		#获取shell脚本所有参数，"$@"会额外将所有参数单独提取为独立字符串
```

### 实践脚本

> 将脚本命名为special_var.sh

```bash
#!/bin/bash

echo "print var in \"\$*\""
for var in "$*"
do
	echo "$var"
done

echo "print var in \"\$@\""
for var in "$@"
do
	echo "$var"
done
```

### 结果展示

```bash
#用空格分开不同的参数
dantalion@Dantalion:~/shell$ bash special_var.sh 1 2 3 4 5
print var in "$*"
1 2 3 4 5
print var in "$@"
1
2
3
4
5
```

## 特殊状态变量

```bash
$?		#上一次命令执行状态返回值，0表示执行成功，非0为失败
$$		#当前脚本的PID
$!		#获取上一次后台执行的程序的PID
$_		#获取上一次执行的命令的最后一个参数
```

### 实践脚本

> 将脚本命名为test.sh；
>
> 用于控制执行脚本的参数值。

```bash
#! /bin/bash
#解释：$#表示获得填入参数的个数，-ne表示不等于；&&{}表示满足[]内条件时则执行{}内的语句；exit 119表示终止进程并返回状态值119

[ $# -ne 2 ] && {
	echo "must be two parameters"
	exit 119
}                                                                                                               echo "correct"

echo "当前脚本PID：$$"
```

### 结果展示

```bash
dantalion@Dantalion:~/shell$ bash test.sh 1
must be two parameters
dantalion@Dantalion:~/shell$ bash test.sh 1 2
correct
当前脚本PID：685

dantalion@Dantalion:~/shell$ $_
2: command not found
```

## 扩展变量

```bash
result=${var:-string}		#如果var的值为空，则返回string给result
result=${var:=string}		#如果var的值为空，则将string赋值给var并且返回给result
${var:?string}				#如果var的值为空，则string作为stderr输出；否则返回var值 -->用于设置变量为空时返回的错误信息
${var:+string}				#如果var的值为空，什么都不做；否则返回string值
```

### 实践

```bash
dantalion@Dantalion:~/shell$ echo ${name:?error}		#当变量为空时主动说明错误信息
-bash: name: error
dantalion@Dantalion:~/shell$ echo ${name:+error}		#当变量非空时说明信息

dantalion@Dantalion:~/shell$ name=aster
dantalion@Dantalion:~/shell$ echo ${name:+error}
error
```

# shell子串

## bash基础内置命令

- `echo`
- `eval`
- `exec`
- `export`
- `read`
- `shift`

### echo

```bash
-n		#不换行输出
-e		#解析字符串中的特殊符号

\n		#表示换行
\r		#表示回车
\t		#制表符，即Tab
\b		#退格

#使用分号隔开不同命令；默认输出会换行
dantalion@Dantalion:~/shell$ echo aster; echo dantalion
aster
dantalion
#不换行打印，使用-n参数
dantalion@Dantalion:~/shell$ echo -n aster; echo dantalion
asterdantalion

#识别\n等特殊符号，使用-e参数
dantalion@Dantalion:~/shell$ echo "aster\ndantalion"
aster\ndantalion
dantalion@Dantalion:~/shell$ echo -e "aster\ndantalion"
aster
dantalion
```

### *printf

> 类似C语言中的printf，可以直接识别特殊符号，默认不换行

```bash
dantalion@Dantalion:~/shell$ printf "aster\n\tdantalion\n"
aster
        dantalion
```

### eval

执行多个命令。

```bash
#先输出内容，再回退到上一级目录
dantalion@Dantalion:~/shell$ eval echo aster; cd ..
aster
dantalion@Dantalion:~$
```

### exec

不创建子进程（类似于docker中直接通过exec进入容器）且执行后续命令，执行完毕后自动exit退出。

```bash
root@Dantalion:~# exec date
Wed Aug 20 12:33:34 CST 2025
dantalion@Dantalion:~$
```

## 基础语法

```bash
${变量}						#返回变量值
${#变量}						#返回变量长度
${变量:n}						#返回变量索引为n的及其之后的所有字符（n为索引值，从0开始）
dantalion@Dantalion:~$ name=1234567
dantalion@Dantalion:~$ echo ${name:4}
567
${变量:n:m}					#提取变量索引为n的及其之后长度为m的所有字符
dantalion@Dantalion:~$ echo ${name:4:2}
56
${变量#string}	 			#从变量开头，删除形如string的字符
dantalion@Dantalion:~$ echo ${name#12}
34567
${变量/old_string/new_string}		#将变量中的第1个old_string替换为new_string
${变量//old_string/new_string}	#将变量中的所有old_string替换为new_string
```

### 统计变量子串长度

```bash
${#变量}
${变量} | wc -L
expr length "${变量}"
```

> [!TIP]
>
> `${#变量}`效率最高，平时尽量使用这个统计方法。

### 批量修改文件名

```bash
dantalion@Dantalion:~/shell$ touch aster_{1..10}_test_.png
dantalion@Dantalion:~/shell$ ls
aster_10_test_.png  aster_2_test_.png  aster_4_test_.png  aster_6_test_.png  aster_8_test_.png  special_var.sh  test.sh
aster_1_test_.png   aster_3_test_.png  aster_5_test_.png  aster_7_test_.png  aster_9_test_.png  test.py

dantalion@Dantalion:~/shell$ echo *.png
aster_10_test_.png aster_1_test_.png aster_2_test_.png aster_3_test_.png aster_4_test_.png aster_5_test_.png aster_6_test_.png aster_7_test_.png aster_8_test_.png aster_9_test_.png
```

```bash
dantalion@Dantalion:~/shell$ for png in `echo *.png`; do mv $png `echo  ${png/_test/}`; done
dantalion@Dantalion:~/shell$ ls
aster_10_.png  aster_2_.png  aster_4_.png  aster_6_.png  aster_8_.png  special_var.sh  test.sh
aster_1_.png   aster_3_.png  aster_5_.png  aster_7_.png  aster_9_.png  test.py
```

> [!IMPORTANT]
>
> 此处使用了反引号``包裹指令，能够取出指令输出的内容。

