#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
  exit 1
fi

add_config() {
  local config="$OPENWRT_DIR/$1"
  local target="$2"
  local device="$3"
  local line="CONFIG_TARGET_DEVICE_${target}_DEVICE_${device}=y"
  local packages="CONFIG_TARGET_DEVICE_PACKAGES_${target}_DEVICE_${device}=\"\""
  local tmp

  if ! grep -Rqs "^define Device/${device}$" "$OPENWRT_DIR/target/linux/mediatek/image"; then
    echo "跳过缺失的设备 profile：$device"
    return 0
  fi

  tmp="$(mktemp)"
  awk '!seen[$0]++' "$config" > "$tmp"
  mv "$tmp" "$config"

  if ! grep -Fxq "$line" "$config"; then
    tmp="$(mktemp)"
    awk -v line="$line" -v packages="$packages" '
      /^CONFIG_TARGET_MULTI_PROFILE=y$/ && !done {
        print
        print line
        print packages
        done=1
        next
      }
      { print }
      END {
        if (!done) {
          print line
          print packages
        }
      }
    ' "$config" > "$tmp"
    mv "$tmp" "$config"
  fi

  if ! grep -Fxq "$packages" "$config"; then
    tmp="$(mktemp)"
    awk -v line="$line" -v packages="$packages" '
      $0 == line && !done {
        print
        print packages
        done=1
        next
      }
      { print }
      END {
        if (!done) print packages
      }
    ' "$config" > "$tmp"
    mv "$tmp" "$config"
  fi
}

echo "正在启用 $OPENWRT_DIR 中已有的 23.05 MT798x 设备定义"

for dev in \
  mt7981-360-t7 \
  one_r35-mini \
  glinet_gl-mt3000 \
  glinet_gl-x3000 \
  glinet_gl-xe3000 \
  glinet_gl-mt2500 \
  cmcc_xr30 \
  cmcc_xr30-emmc \
  honor_fur-602 \
  ikuai_q3000 \
  newland_nl-wr8103 \
  newland_nl-wr9103 \
  routerich_ax3000 \
  ruijie_rg-x30e \
  ruijie_rg-x30e-firmware2 \
  ruijie_rg-x30e-stock \
  ruijie_rg-x30e-pro \
  ruijie_rg-x30e-pro-firmware2 \
  ruijie_rg-x30e-pro-stock \
  nokia_ea0326gmp \
  nradio_wt9103 \
  nradio_wt9103_512m; do
  add_config "defconfig/mt7981-ax3000.config" "mediatek_mt7981" "$dev"
done

add_config "defconfig/mt7986-ax4200.config" "mediatek_mt7986" "BPI-R3MINI-NAND-110M"

for dev in \
  jdcloud_re-cp-03 \
  ruijie-rg-x60-pro \
  ruijie-rg-x60-pro-stock \
  ruijie-rg-x60-pro-uboot \
  zyxel_ex5700; do
  add_config "defconfig/mt7986-ax6000.config" "mediatek_mt7986" "$dev"
done

echo "23.05 已有设备定义已启用。"
