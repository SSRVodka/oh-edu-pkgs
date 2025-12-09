#!/bin/bash
# 生成 wheel RECORD 文件

# 检查是否提供了目录参数
if [ $# -eq 0 ]; then
    echo "Usage: $0 directory1 [directory2 ...]" >&2
    exit 1
fi

# 遍历所有传入的目录
for dir in "$@"; do
    # 检查目录是否存在
    if [ ! -d "$dir" ]; then
        echo "Error: $dir is not a directory" >&2
        continue
    fi
    
    # 递归查找所有普通文件，处理含空格和特殊字符的文件名
    find "$dir" -type f -print0 | while IFS= read -r -d '' file; do
        # 检查路径是否包含__pycache__
        if [[ "$file" == *__pycache__* ]]; then
            printf "%s,,\n" "$file"
        else
            # 计算SHA256哈希值（仅取摘要部分）
            sha=$(sha256sum "$file" | awk '{print $1}')
            # 获取文件字节大小
            size=$(stat -c '%s' "$file")
            # 格式化输出
            printf "%s,sha256=%s,%s\n" "$file" "$sha" "$size"
        fi
    done
done