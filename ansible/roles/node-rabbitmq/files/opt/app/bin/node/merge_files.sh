#!/bin/bash

# 使用方法提示
usage() {
  echo "Usage: $0 <file1> <file2> <outputfile>"
  exit 1
}

# 检查参数数量
if [ "$#" -ne 3 ]; then
  usage
fi

# 赋值参数到变量
file1="$1"
file2="$2"
outputfile="$3"

# 清理并合并两个文件
merge_files() {
  # 清理第一个文件并写入输出文件
  sed 's/[[:space:]]*=[[:space:]]*/=/' "$file1" > "$outputfile"

  # 逐行读取第二个文件
  while IFS= read -r line; do
    # 清理空格
    clean_line=$(echo "$line" | sed 's/[[:space:]]*=[[:space:]]*/=/')
    # 提取key
    key=$(echo "$clean_line" | cut -d '=' -f 1)

    # 检查键是否已经在输出文件中
    if ! grep -q "^${key}=" "$outputfile"; then
      # 如果不在，追加到输出文件中
      echo "$clean_line" >> "$outputfile"
    fi
  done < <(sed 's/[[:space:]]*=[[:space:]]*/=/' "$file2")
}

# 检查文件是否存在并合并
if [ -f "$file1" ] && [ -f "$file2" ]; then
  merge_files
  echo "Files $file1 and $file2 have been merged into $outputfile."
elif [ -f "$file1" ]; then
  sed 's/[[:space:]]*=[[:space:]]*/=/' "$file1" > "$outputfile"
  echo "File $file1 has been copied to $outputfile as file $file2 does not exist."
elif [ -f "$file2" ]; then
  sed 's/[[:space:]]*=[[:space:]]*/=/' "$file2" > "$outputfile"
  echo "File $file2 has been copied to $outputfile as file $file1 does not exist."
else
  echo "Neither $file1 nor $file2 exist."
  exit 1
fi