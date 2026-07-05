#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$PATCH_DIR/files"
MT7986_DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7986_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7986.mk"
MT7986_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7986/base-files/etc/board.d/02_network"
MT7986_UPGRADE="$OPENWRT_DIR/target/linux/mediatek/mt7986/base-files/lib/upgrade/platform.sh"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
  exit 1
fi

insert_before_marker() {
  local file="$1"
  local marker="$2"
  local block_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
    { print }
    END {
      if (!done) exit 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

insert_before_marker_after() {
  local file="$1"
  local anchor="$2"
  local marker="$3"
  local block_file="$4"
  local tmp

  tmp="$(mktemp)"
  awk -v anchor="$anchor" -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    index($0, anchor) {
      seen_anchor = 1
    }
    seen_anchor && index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
    { print }
    END {
      if (!done) exit 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

has_between() {
  local file="$1"
  local start="$2"
  local stop="$3"
  local needle="$4"

  awk -v start="$start" -v stop="$stop" -v needle="$needle" '
    index($0, start) { in_range = 1 }
    in_range && index($0, needle) { found = 1 }
    in_range && index($0, stop) { in_range = 0 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

mkdir -p "$MT7986_DTS_DIR"
if [ ! -f "$FILES_DIR/mt7986a-zyxel-ex5700.dts" ]; then
  echo "错误：缺少 DTS 载荷文件：$FILES_DIR/mt7986a-zyxel-ex5700.dts" >&2
  exit 1
fi
install -m 0644 "$FILES_DIR/mt7986a-zyxel-ex5700.dts" "$MT7986_DTS_DIR/mt7986a-zyxel-ex5700.dts"

if ! grep -q '^define Device/zyxel_ex5700$' "$MT7986_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/zyxel_ex5700
  DEVICE_VENDOR := Zyxel
  DEVICE_MODEL := EX5700
  DEVICE_DTS := mt7986a-zyxel-ex5700
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := zyxel,ex5700
  DEVICE_PACKAGES := $(MT7986_USB_PKGS)
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 256k
  PAGESIZE := 4096
  IMAGE_SIZE := 485888k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += zyxel_ex5700

DEVICE
  insert_before_marker "$MT7986_IMAGE" "define Device/tplink_tl-common" "$block"
  rm -f "$block"
fi

if ! grep -q 'zyxel,ex5700)' "$MT7986_NETWORK"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	zyxel,ex5700)
		ucidef_set_interfaces_lan_wan "eth0" "eth1"
		ucidef_add_switch "switch0" \
			"0:lan:3" "1:lan:4" "2:lan:5" "5:lan:2" "6u@eth0"
		;;
NETWORK
  insert_before_marker "$MT7986_NETWORK" "bananapi,bpi-r3mini*)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7986_UPGRADE" "platform_do_upgrade()" "platform_check_image()" "zyxel,ex5700"; then
  block="$(mktemp)"
  printf '\tzyxel,ex5700 |\\\n' > "$block"
  insert_before_marker_after "$MT7986_UPGRADE" "platform_do_upgrade()" "	*snand*)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7986_UPGRADE" "platform_check_image()" "return 0" "zyxel,ex5700"; then
  block="$(mktemp)"
  printf '\tzyxel,ex5700 |\\\n' > "$block"
  insert_before_marker_after "$MT7986_UPGRADE" "platform_check_image()" "	*snand* |" "$block"
  rm -f "$block"
fi

echo "Zyxel EX5700 23.05 适配已准备好。"
