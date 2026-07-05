#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
export GOPROXY="https://goproxy.cn,direct"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="$SCRIPT_DIR/openwrt"
ARTIFACT_DIR="$SCRIPT_DIR/artifacts"
JOBS="${JOBS:-2}"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-8}"

VARIANTS=(
  "mt7981-ax3000:mt7981"
  "mt7986-ax4200:mt7986"
  "mt7986-ax6000-256m:mt7986"
  "mt7986-ax6000:mt7986"
)

echo "========================================="
echo "  ImmortalWrt MT798x 全量编译"
echo "  开始时间: $(date)"
echo "  编译线程: $JOBS"
echo "========================================="

rm -rf "$ARTIFACT_DIR"

cd "$OPENWRT_DIR"
bash "$SCRIPT_DIR/01_prepare.sh"

for entry in "${VARIANTS[@]}"; do
  variant="${entry%%:*}"
  platform="${entry##*:}"

  echo ""
  echo "========== $variant（平台: $platform）=========="
  echo "开始时间: $(date)"

  cd "$OPENWRT_DIR"
  bash "$SCRIPT_DIR/scripts/apply_2305_adapted_devices.sh" "$OPENWRT_DIR"
  bash "$SCRIPT_DIR/scripts/enable_2305_existing_devices.sh" "$OPENWRT_DIR"

  cat "defconfig/${variant}.config" > .config
  bash ../02_add_package.sh
  make defconfig

  # 下载新增依赖（增量）
  make download -j"$DOWNLOAD_JOBS"

  # 编译
  make -j"$JOBS" || make -j1 V=s

  # 收集产物
  mkdir -p "$ARTIFACT_DIR/$variant"
  find "bin/targets/mediatek/$platform/" -name "*squashfs*" \
    -exec cp {} "$ARTIFACT_DIR/$variant/" \;

  echo "完成 $variant：$(ls "$ARTIFACT_DIR/$variant" | wc -l) 个文件"
done

echo ""
echo "========================================="
echo "  全部完成：$(date)"
echo "========================================="

# 汇总
for d in "$ARTIFACT_DIR"/*/; do
  echo "$(basename $d)：$(ls $d | wc -l) 个文件"
done
du -sh "$ARTIFACT_DIR/"
