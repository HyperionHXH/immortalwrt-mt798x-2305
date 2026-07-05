#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$PATCH_DIR/files"
MT7981_DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7981_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7981.mk"
MT7981_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/02_network"
MT7981_LEDS="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/01_leds"
MT7981_UPGRADE="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "error: OPENWRT_DIR does not look like an ImmortalWrt tree: $OPENWRT_DIR" >&2
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

install_dts() {
  local name="$1"
  local src="$FILES_DIR/$name"

  if [ ! -f "$src" ]; then
    echo "error: missing DTS payload: $src" >&2
    exit 1
  fi

  install -m 0644 "$src" "$MT7981_DTS_DIR/$name"
}

mkdir -p "$MT7981_DTS_DIR"
install_dts mt7981-honor-fur-602.dts
install_dts mt7981-newland-nl-wr8103.dts
install_dts mt7981-newland-nl-wr9103.dts
install_dts mt7981-routerich-ax3000.dts

if ! grep -q '^define Device/honor_fur-602$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602
  DEVICE_DTS := mt7981-honor-fur-602
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := honor,fur-602
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += honor_fur-602

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/konka_komi-a31" "$block"
  rm -f "$block"
fi

if ! grep -q '^define Device/newland_nl-wr8103$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/newland_nl-wr8103
  DEVICE_VENDOR := Newland
  DEVICE_MODEL := NL-WR8103
  DEVICE_DTS := mt7981-newland-nl-wr8103
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := newland,nl-wr8103
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += newland_nl-wr8103

define Device/newland_nl-wr9103
  DEVICE_VENDOR := Newland
  DEVICE_MODEL := NL-WR9103
  DEVICE_DTS := mt7981-newland-nl-wr9103
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := newland,nl-wr9103
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += newland_nl-wr9103

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/nradio_wt9103" "$block"
  rm -f "$block"
fi

if ! grep -q '^define Device/routerich_ax3000$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/routerich_ax3000
  DEVICE_VENDOR := Routerich
  DEVICE_MODEL := AX3000
  DEVICE_DTS := mt7981-routerich-ax3000
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := routerich,ax3000 mediatek,mt7981-spim-snand-rfb
  DEVICE_PACKAGES := $(MT7981_USB_PKGS)
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
  KERNEL_IN_UBI := 1
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += routerich_ax3000

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/nradio_wt9103" "$block"
  rm -f "$block"
fi

if ! grep -q 'honor,fur-602' "$MT7981_NETWORK"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	*honor,fur-602*)
		ucidef_set_interfaces_lan_wan "eth0.1" "eth0.2"
		ucidef_add_switch "switch0" \
			"1:lan:3" "2:lan:2" "3:lan:1" "0:wan" "6t@eth0"
		;;
	*newland,nl-wr8103*)
		ucidef_set_interfaces_lan_wan "eth0" "eth1"
		ucidef_add_switch "switch0" \
			"0:lan" "1:lan" "2:lan" "6u@eth0"
		;;
	*newland,nl-wr9103*)
		ucidef_set_interfaces_lan_wan "eth0" "eth1"
		ucidef_add_switch "switch0" \
			"1:lan" "2:lan" "3:lan" "6u@eth0"
		;;
	routerich,ax3000)
		ucidef_set_interfaces_lan_wan "eth0" "eth1"
		ucidef_add_switch "switch0" \
			"0:lan:1" "2:lan:2" "3:lan:3" "4:wan" "6u@eth0" "5u@eth1"
		;;
NETWORK
  insert_before_marker "$MT7981_NETWORK" '	*cmcc,a10*)' "$block"
  rm -f "$block"
fi

if ! grep -q 'macaddr_add "$wifi_mac" -2' "$MT7981_NETWORK"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	*newland,nl-wr8103*)
		local wifi_mac=$(mtd_get_mac_binary Factory 0x4)
		lan_mac=$(macaddr_add $wifi_mac -1)
		wan_mac=$(macaddr_add $wifi_mac -2)
		;;
	routerich,ax3000)
		local wifi_mac="$(mtd_get_mac_binary $part_name 0x4)"
		label_mac=$(macaddr_add "$wifi_mac" -2)
		lan_mac=$(macaddr_add "$wifi_mac" -1)
		wan_mac=$label_mac
		local b1dat="/etc/wireless/mediatek/mt7981.dbdc.b1.dat"
		if [ -f "$b1dat" ]; then
			local b1mac="$(macaddr_add "$wifi_mac" 1)"
			sed -i '/^MacAddress=/d' "$b1dat"
			echo "MacAddress=$b1mac" >> "$b1dat"
		fi
		;;
NETWORK
  insert_before_marker_after "$MT7981_NETWORK" "nokia,ea0326gmp)" "nradio,wt9103)" "$block"
  rm -f "$block"
fi

if ! grep -q 'routerich,ax3000)' "$MT7981_LEDS"; then
  block="$(mktemp)"
  cat > "$block" <<'LEDS'
routerich,ax3000)
	ucidef_set_led_switch "lan1" "LAN1" "blue:lan1" "switch0" "0x01"
	ucidef_set_led_switch "lan2" "LAN2" "blue:lan2" "switch0" "0x04"
	ucidef_set_led_switch "lan3" "LAN3" "blue:lan3" "switch0" "0x08"
	ucidef_set_led_switch "wan" "WAN" "blue:wan" "switch0" "0x10"
	ucidef_set_led_switch "wan off" "WAN Off" "red:wan" "switch0" "0x10" "" "link"
	ucidef_set_led_netdev "wlan2g" "WLAN 2G" "blue:wlan2g" "ra0"
	ucidef_set_led_netdev "wlan5g" "WLAN 5G" "red:wlan5g" "rax0"
	;;
*newland,nl-wr8103*)
	ucidef_set_led_default "red" "RED" "red:status" "0"
	ucidef_set_led_default "green" "GREEN" "green:status" "0"
	ucidef_set_led_default "blue" "BLUE" "blue:status" "1"
	;;
LEDS
  insert_before_marker "$MT7981_LEDS" "nradio,wt9103)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_do_upgrade()" "platform_check_image()" "routerich,ax3000"; then
  block="$(mktemp)"
  cat > "$block" <<'UPGRADE'
	*honor,fur-602* |\
	*newland,nl-wr8103* |\
	newland,nl-wr9103 |\
	routerich,ax3000 |\
UPGRADE
  insert_before_marker_after "$MT7981_UPGRADE" "platform_do_upgrade()" "	*konka,komi-a31*" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_check_image()" "return 0" "routerich,ax3000"; then
  block="$(mktemp)"
  cat > "$block" <<'UPGRADE'
	*honor,fur-602* |\
	*newland,nl-wr8103* |\
	newland,nl-wr9103 |\
	routerich,ax3000 |\
UPGRADE
  insert_before_marker_after "$MT7981_UPGRADE" "platform_check_image()" "	*konka,komi-a31*" "$block"
  rm -f "$block"
fi

echo "MT7981 legacy GSW device adaptations ready."
