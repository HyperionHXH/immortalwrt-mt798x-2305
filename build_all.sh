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
echo "  ImmortalWrt MT798x Build All"
echo "  Start: $(date)"
echo "  Jobs: $JOBS"
echo "========================================="

rm -rf "$ARTIFACT_DIR"

cd "$OPENWRT_DIR"
bash "$SCRIPT_DIR/01_prepare.sh"

for entry in "${VARIANTS[@]}"; do
  variant="${entry%%:*}"
  platform="${entry##*:}"

  echo ""
  echo "========== $variant (platform: $platform) =========="
  echo "Start: $(date)"

  cd "$OPENWRT_DIR"
  bash "$SCRIPT_DIR/scripts/apply_2305_adapted_devices.sh" "$OPENWRT_DIR"
  bash "$SCRIPT_DIR/scripts/enable_2305_existing_devices.sh" "$OPENWRT_DIR"

  cat "defconfig/${variant}.config" > .config
  bash ../02_add_package.sh
  make defconfig

  # Download new deps (incremental)
  make download -j"$DOWNLOAD_JOBS"

  # Compile
  make -j"$JOBS" || make -j1 V=s

  # Collect artifacts
  mkdir -p "$ARTIFACT_DIR/$variant"
  find "bin/targets/mediatek/$platform/" -name "*squashfs*" \
    -exec cp {} "$ARTIFACT_DIR/$variant/" \;

  echo "Done $variant: $(ls "$ARTIFACT_DIR/$variant" | wc -l) files"
done

echo ""
echo "========================================="
echo "  ALL DONE at $(date)"
echo "========================================="

# Summary
for d in "$ARTIFACT_DIR"/*/; do
  echo "$(basename $d): $(ls $d | wc -l) files"
done
du -sh "$ARTIFACT_DIR/"
