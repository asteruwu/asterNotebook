# 二分查找插入位置

Given a sorted array of distinct integers and a target value, return the index if the target is found. If not, return the index where it would be if it were inserted in order.

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func searchInsert(nums []int, target int) int {
    Left := 0
    Right := len(nums)-1

    for Left <= Right {
        Mid := (Left + Right) / 2

        if nums[Mid] == target {
            return Mid
        } else if nums[Mid] > target {
            Right = Mid - 1
        } else {
            Left = Mid + 1
        }
    }
    return Left
}
```

最终`return Left`的原因：

- 把数组里的数分成两派：

  - **左派（比 target 小）**：你的代码会让 `Left` 不断右移，跳过它们。

  - **右派（比 target 大）**：你的代码会让 `Right` 不断左移，避开它们。

- 当循环结束时 (`Left > Right`)：

  - `Right` 会停在 **“比 target 小”的最后一个数** 上。

  - `Left` 会停在 **“比 target 大”的第一个数** 上（或者数组末尾）。

# 二叉树的中序遍历

Given the `root` of a binary tree, return *the inorder traversal of its nodes' values*.

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func inorderTraversal(root *TreeNode) []int {
    var res []int

    var dfs func(node *TreeNode)
    dfs = func(node *TreeNode) {
        if node == nil {
            return
        }
        dfs(node.Left)
        res = append(res, node.Val)
        dfs(node.Right)
    }
    dfs(root)
    return res
}
```

`return`：

- **作用**： 当 `dfs` 被叫到一个空的位置（比如叶子节点的左下方，那里什么都没有，是 `nil`）时，**退回上一步**；
- **如果没有**： 程序会试图访问 `nil.Left` 或 `nil.Val`，直接报空指针错误（Panic）崩溃；或者无限循环调用，直到内存爆满。

# 判断对称树

<img src="../../dio图表/SRE/Go_interface-LC101.drawio.svg" alt="Go_interface-LC101.drawio" style="zoom:120%;" />

Given the `root` of a binary tree, *check whether it is a mirror of itself* (i.e., symmetric around its center).

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func isSymmetric(root *TreeNode) bool {
    if root == nil {
        return true
    }
    return check(root.Left, root.Right)
}

func check(p *TreeNode, q *TreeNode) bool {
    if p == nil && q == nil {
        return true
    }
    if p == nil || q == nil || p.Val != q.Val {
        return false
    }

    return check(p.Left, q.Right) && check(p.Right, q.Left)
}
```

**核心思路：**

要判断这棵树是不是对称的，其实不是看 `root` 节点（它只是个入口），而是看它的 **左子树** 和 **右子树** 是不是互为镜像。

想像把这棵树从中间（虚线处）对折：

- 左边的 `2` 必须等于右边的 `2`。
- **左边 `2` 的左孩子 (`3`)** 必须对应 **右边 `2` 的右孩子 (`3`)** —— **(外侧对外侧)**
- **左边 `2` 的右孩子 (`4`)** 必须对应 **右边 `2` 的左孩子 (`4`)** —— **(内侧对内侧)**

# 二叉树最大深度

Given the `root` of a binary tree, return *its maximum depth*.

A binary tree's **maximum depth** is the number of nodes along the longest path from the root node down to the farthest leaf node.

## Top-Down

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func maxDepth(root *TreeNode) int {
    depth := 0
    return CalculateDepth(root, depth)
}

func CalculateDepth(root *TreeNode, d int) int {
    if root == nil {
        return d
    }
    d++
    leftDepth := CalculateDepth(root.Left, d)
    rightDepth := CalculateDepth(root.Right, d)

    if leftDepth > rightDepth {
        return leftDepth
    } else {
        return rightDepth
    }
}
```

- **逻辑**：你派了一个函数（`CalculateDepth`），手里拿着个计步器（`d`）。
- **动作**：
  1. 每走一步（递归调用），就把计步器 `d++`。
  2. 走到死胡同（`root == nil`）时，看一眼计步器，读出 `d`，然后返回。
  3. 最后在分叉口比较左右两边谁带回来的数字大。

- **特点**：把**状态（深度 d）通过参数一层一层传下去**。

## Bottom-Up

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func maxDepth(root *TreeNode) int {
    if root == nil {
        return 0
    }

    leftDepth := maxDepth(root.Left)
    rightDepth := maxDepth(root.Right)

    if leftDepth > rightDepth {
        return leftDepth + 1
    } else {
        return rightDepth + 1
    }
}
```

**逻辑**：

- 我是当前节点，我不用自己记步数。
- 我只问左子树：“你那儿多深？”
- 再问右子树：“你那儿多深？”
- **我的深度 = Max(左，右) + 1（我自己）**。

# 回溯 | 多叉树排列组合

> [!IMPORTANT]
>
> #### **回溯类问题**
>
> **识别标志**：题目要求“所有组合”、“所有排列”、“所有路径”、“穷举”

Given a string containing digits from `2-9` inclusive, return all possible letter combinations that the number could represent. Return the answer in **any order**.

A mapping of digits to letters (just like on the telephone buttons) is given below. Note that 1 does not map to any letters.

<img src="https://assets.leetcode.com/uploads/2022/03/15/1200px-telephone-keypad2svg.png" alt="img" style="zoom: 33%;" />



<img src="../../dio图表/SRE/Go_interface-LC17.drawio.svg" alt="Go_interface-LC17.drawio" style="zoom:120%;" />

```go
func letterCombinations(digits string) []string {
    phoneMap := map[byte]string{
        '2': "abc", '3': "def", '4': "ghi", '5': "jkl",
        '6': "mno", '7': "pqrs", '8': "tuv", '9': "wxyz",
    }

    if len(digits) == 0 {
        return []string{}
    }

    var res []string
    var dfs func(index int, path string)
    dfs = func(index int, path string) {
        if index == len(digits) {
            res = append(res, path)
            return
        }

        digit := digits[index]
        letters := phoneMap[digit]

        for _, char := range letters {
            dfs(index + 1, path + string(char))
        }
    }

    dfs(0, "")
    return res
}
```

以输入`digits="23"`为例：

定义函数 `dfs(index, path)`：

- **`index` (当前层级)**：代表正在处理输入字符串的第几个数字（决定了树的深度）。
- **`path` (当前路径)**：代表这一路走来手里已经拿着的字符串。

**0. 初始状态**

- 调用 `dfs(0, "")`。

**1. 第一层递归 (处理 '2')**

- 拿到 `'2'` 对应的字母表 `['a', 'b', 'c']`。
- **选择 'a'**：
  - 调用 `dfs(1, "a")` -> 进入下一层。

**2. 第二层递归 (处理 '3')**

- 拿到 `'3'` 对应的字母表 `['d', 'e', 'f']`。
- **选择 'd'**：
  - 调用 `dfs(2, "ad")` -> 进入下一层。

**3. 第三层递归 (触底结算)**

- `index` 是 2，等于输入长度 "23" 的长度。**撞墙！**
- 说明一条路走通了。把 `"ad"` 加入结果集 `res`。
- **Return (回溯)** -> 回到第二层。

**4. 回到第二层 (继续处理 '3' 的剩余选项)**

- 刚才选了 'd' 回来了。
- 现在**选择 'e'**：
  - 调用 `dfs(2, "ae")` -> 触底 -> 存入 "ae" -> Return。
- 现在**选择 'f'**：
  - 调用 `dfs(2, "af")` -> 触底 -> 存入 "af" -> Return。
- '3' 的选项全试完了，**Return** -> 回到第一层。

**5. 回到第一层 (继续处理 '2' 的剩余选项)**

- 刚才选了 'a' 这一整支（衍生出了 ad, ae, af）都跑完了。
- 现在**选择 'b'**：
  - 调用 `dfs(1, "b")`... (重复上述过程，生成 bd, be, bf)。

# 有序数组转为二叉搜索树

本质上是二分查找的逆过程。

Given an integer array `nums` where the elements are sorted in **ascending order**, convert it to a **height-balanced** *binary search tree*.

**height-balanced**：A **height-balanced** binary tree is a binary tree in which the depth of the two subtrees of every node never differs by more than one.

```go
/**
 * Definition for a binary tree node.
 * type TreeNode struct {
 *     Val int
 *     Left *TreeNode
 *     Right *TreeNode
 * }
 */
func sortedArrayToBST(nums []int) *TreeNode {
    if len(nums) == 0 {
        return nil
    }
    mid := len(nums) / 2
    root := &TreeNode{Val: nums[mid]}

    root.Left = sortedArrayToBST(nums[:mid])
    root.Right = sortedArrayToBST(nums[mid+1:])

    return root
}
```

- **分治思想**：这道题是标准的分治法。把大问题（建整棵树）拆成两个一模一样的小问题（建左子树、建右子树）。
- **二分查找的变体**：二分查找是 `Left + (Right - Left) / 2` 去**找**东西；这道题是用同样的逻辑去**造**东西。
