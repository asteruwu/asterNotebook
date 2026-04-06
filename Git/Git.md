# 工作区域

## 本地

- **工作目录（Working Directory）**

  平时存放代码的地方.

- **暂存区（Stage/Index）**

  临时存放改动，实际上只是一个文件.

- **资源库（Repository/Git Directory）**

  安全存放数据的位置，这里有提交到所有版本的数据；HEAD指向最新放入仓库的版本.

## 远程

- **Git仓库（Remote Directory）**

  比如GitHub，是托管代码的服务器.

# 工作流程

**1.在工作目录中添加/修改文件；**

**2.将需要进行版本管理的（所有）文件放入暂存区；**

```bash
$ git add .
```

**3.将暂存区文件提交到git仓库；**

```bash
$ git commit -m "info"
```

***克隆远程仓库**

```bash
$ git clone [url]
```

***将远程仓库改动合并到本地**

```bash
$ git pull --rebase origin master
```

**4.提交到远程仓库；**

```bash
$ git remote add origin [远程仓库url]
$ git push -u origin master
```



# 文件操作

## 常用命令

```bash
#查看文件状态
$ git status
On branch master

No commits yet

Untracked files:#没有被追踪的文件
  (use "git add <file>..." to include in what will be committed)
        hello.txt 

nothing added to commit but untracked files present (use "git add" to track)

#提交到暂存区后再查看状态
$ git add .

$ git status
On branch master

No commits yet

Changes to be committed:#已添加新文件
  (use "git rm --cached <file>..." to unstage)
        new file:   hello.txt

#将暂存区文件提交到本地仓库
$ git commit -m "new file hello.txt"#-m 提交信息
[master (root-commit) 4248062] new file hello.txt
 1 file changed, 0 insertions(+), 0 deletions(-)
 create mode 100644 hello.txt
```

# 分支

## 类型

- ### **master：**主分支

- ### **dev：**开发用分支

- ### **v4.0：**不同版本分支

## 常用命令

```bash
#查看本地的所有分支
$ git branch
* master

#查看远程仓库中的分支
$ git branch -r
  origin/master
  
#新建分支
git branch [branch-name]
$ git branch dev
```

