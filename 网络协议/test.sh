#!/bin/bash

# 检查是否安装了 Typora
if ! command -v typora &> /dev/null
then
    echo "Typora 未安装，请先安装它。"
    exit 1
fi

# 遍历当前目录下的所有 .md 文件
for file in *.md; do
    # 判断文件是否存在
    if [[ -f "$file" ]]; then
        # 输出转换信息
        echo "正在转换 $file 到 PDF..."
        # 使用 Typora 转换为 PDF
        typora "$file" --export "${file%.md}.pdf"
        echo "$file 转换完成!"
    fi
done

echo "所有文件转换完成!"
