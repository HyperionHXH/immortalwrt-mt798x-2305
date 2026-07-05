#!/usr/bin/env bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$WRAPPER_DIR/patches/2305"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "error: OPENWRT_DIR does not look like an ImmortalWrt tree: $OPENWRT_DIR" >&2
  exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
  echo "No 23.05 adapted-device patches found."
  exit 0
fi

apply_one_patch() {
  local patch_file="$1"
  local patch_name
  patch_name="$(basename "$patch_file")"

  if git -C "$OPENWRT_DIR" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Already applied: $patch_name"
    return 0
  fi

  if git -C "$OPENWRT_DIR" apply --check "$patch_file"; then
    git -C "$OPENWRT_DIR" apply "$patch_file"
    echo "Applied: $patch_name"
    return 0
  fi

  echo "error: failed to apply $patch_name" >&2
  echo "Review the patch against the current 23.05 source tree before continuing." >&2
  exit 1
}

echo "Applying 23.05 adapted MT798x device patches in $OPENWRT_DIR"

shopt -s nullglob
for patch_file in "$PATCH_DIR"/*.patch; do
  apply_one_patch "$patch_file"
done

for script_file in "$PATCH_DIR"/*.sh; do
  echo "Running adapted-device script: $(basename "$script_file")"
  bash "$script_file" "$OPENWRT_DIR"
done
shopt -u nullglob

echo "23.05 adapted device patches ready."
