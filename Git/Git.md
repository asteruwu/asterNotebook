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
$ git pull --rebase origin main
```

**4.提交到远程仓库；**

```bash
$ git remote add origin [远程仓库url]
$ git push -u origin master
```

# 常用命令

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

### 将当前分支的提交 rebase 合入主分支

```bash
#更新主分支
$ git checkout main
$ git pull origin main

#将主分支变基到当前分支
$ git checkout <current branch>
$ git rebase main

#合并
$ git checkout main
$ git merge <current branch>

#推送
$ git push origin main
```

### 将当前分支未提交代码 copy 到新分支（用于测试）

```bash
# 记下当前分支名，并确认改动
git branch --show-current
git status --short

# 暂存已跟踪改动和未跟踪文件
git stash push -u -m "save local work for remote test"

# 从当前分支创建测试分支，并恢复改动
git checkout -b test/<测试分支名>
git stash apply "stash@{0}"

# 在测试分支提交并推送
git add <需要提交的文件>
git commit -m "<提交说明>"
git push -u origin test/<测试分支名>

# 在当前分支弹出未提交文件
git stash apply "stash@{0}"
```

### 修改最近一次 commit 的信息

```bash
# 1. 修改信息
git commit --amend -m "新的提交信息"
# 或者不加 -m，会打开编辑器让你改

# 2. 强推覆盖远程
git push --force-with-lease origin feat/mock-server-initialize
```

### 查看/修改个人信息

```bash
git config --global user.name  # "new name"
git config --global user.email # "new email"
```

### 修改已发布分支名

```bash
# 1. 切换到该分支，更改名字
git branch -m new-name

# 2. 推送到远程
git push origin -u new-name

# 3. 删除远程旧分支
git push origin --delete old-name
```