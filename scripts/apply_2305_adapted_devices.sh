#!/usr/bin/env bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$WRAPPER_DIR/patches/2305"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
  exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
  echo "没有找到 23.05 设备适配补丁。"
  exit 0
fi

apply_one_patch() {
  local patch_file="$1"
  local patch_name
  patch_name="$(basename "$patch_file")"

  if git -C "$OPENWRT_DIR" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "已应用，跳过：$patch_name"
    return 0
  fi

  if git -C "$OPENWRT_DIR" apply --check "$patch_file"; then
    git -C "$OPENWRT_DIR" apply "$patch_file"
    echo "已应用：$patch_name"
    return 0
  fi

  echo "错误：应用 $patch_name 失败" >&2
  echo "继续前请按当前 23.05 源码树重新检查这个补丁。" >&2
  exit 1
}

echo "正在向 $OPENWRT_DIR 应用 23.05 MT798x 设备适配补丁"

shopt -s nullglob
for patch_file in "$PATCH_DIR"/*.patch; do
  apply_one_patch "$patch_file"
done

for script_file in "$PATCH_DIR"/*.sh; do
  echo "运行设备适配脚本：$(basename "$script_file")"
  bash "$script_file" "$OPENWRT_DIR"
done
shopt -u nullglob

echo "23.05 设备适配补丁已准备好。"
