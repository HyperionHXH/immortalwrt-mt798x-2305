#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_SOURCE_COMMIT="${REPO_COMMIT:-8fd3008be125e590664b311e3aaedee344adc354}"
DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7981_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7981.mk"
MT7986_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7986.mk"
MT7981_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/02_network"
MT7981_UPGRADE="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh"

fail() {
  echo "适配校验失败：$*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "缺少文件 $1"
}

device_block_has() {
  local image_file="$1"
  local profile="$2"
  local expected="$3"

  awk -v start="define Device/$profile" -v expected="$expected" '
    $0 == start { in_device = 1; count++ }
    in_device && index($0, expected) { found = 1 }
    in_device && $0 == "endef" { in_device = 0 }
    END { exit !(count == 1 && found) }
  ' "$image_file"
}

case_block_has() {
  local file="$1"
  local case_line="$2"
  local expected="$3"

  awk -v case_line="$case_line" -v expected="$expected" '
    $0 == case_line { in_case = 1; count++ }
    in_case && index($0, expected) { found = 1 }
    in_case && /^[[:space:]]*;;[[:space:]]*$/ { in_case = 0 }
    END { exit !(count == 1 && found) }
  ' "$file"
}

dts_node_has() {
  local file="$1"
  local node="$2"
  local expected="$3"

  awk -v node="$node" -v expected="$expected" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
    }
    line == node " {" { in_node = 1; count++ }
    in_node && index($0, expected) { found = 1 }
    in_node && line == "};" { in_node = 0 }
    END { exit !(count == 1 && found) }
  ' "$file"
}

check_profile() {
  local image_file="$1"
  local config_file="$2"
  local target="$3"
  local profile="$4"
  local dts="$5"
  local compatible="$6"

  require_file "$DTS_DIR/$dts.dts"
  device_block_has "$image_file" "$profile" "DEVICE_DTS := $dts" || \
    fail "$profile 的设备定义缺失、重复或 DTS 不匹配"
  grep -Fq "compatible = \"$compatible\"" "$DTS_DIR/$dts.dts" || \
    fail "$dts.dts 缺少 compatible=$compatible"
  grep -Fqx "CONFIG_TARGET_DEVICE_${target}_DEVICE_${profile}=y" "$config_file" || \
    fail "$profile 没有在 $config_file 中启用"
}

for script in "$WRAPPER_DIR"/*.sh "$WRAPPER_DIR"/scripts/*.sh "$WRAPPER_DIR"/patches/2305/*.sh; do
  bash -n "$script" || fail "脚本语法错误：$script"
done

actual_source_commit="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
[ "$actual_source_commit" = "$EXPECTED_SOURCE_COMMIT" ] || \
  fail "源码提交为 $actual_source_commit，尚未审查；预期 $EXPECTED_SOURCE_COMMIT"

require_file "$MT7981_IMAGE"
require_file "$MT7986_IMAGE"
require_file "$MT7981_NETWORK"
require_file "$MT7981_UPGRADE"

mt7981_config="$OPENWRT_DIR/defconfig/mt7981-ax3000.config"
mt7986_config="$OPENWRT_DIR/defconfig/mt7986-ax6000.config"

check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 cmcc_xr30 \
  mt7981-cmcc-xr30 cmcc,xr30
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 cmcc_xr30-emmc \
  mt7981-cmcc-xr30-emmc cmcc,xr30-emmc
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 honor_fur-602 \
  mt7981-honor-fur-602 honor,fur-602
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 ikuai_q3000 \
  mt7981-ikuai-q3000 ikuai,q3000
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 newland_nl-wr8103 \
  mt7981-newland-nl-wr8103 newland,nl-wr8103
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 newland_nl-wr9103 \
  mt7981-newland-nl-wr9103 newland,nl-wr9103
check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 routerich_ax3000 \
  mt7981-routerich-ax3000 routerich,ax3000

for suffix in '' '-firmware2' '-stock'; do
  check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 "ruijie_rg-x30e$suffix" \
    "mt7981-ruijie-rg-x30e$suffix" "ruijie,rg-x30e$suffix"
  check_profile "$MT7981_IMAGE" "$mt7981_config" mediatek_mt7981 "ruijie_rg-x30e-pro$suffix" \
    "mt7981-ruijie-rg-x30e-pro$suffix" "ruijie,rg-x30e-pro$suffix"
done

check_profile "$MT7986_IMAGE" "$mt7986_config" mediatek_mt7986 ruijie-rg-x60-pro-stock \
  mt7986a-ruijie-rg-x60-pro-stock ruijie,rg-x60-pro-stock
check_profile "$MT7986_IMAGE" "$mt7986_config" mediatek_mt7986 zyxel_ex5700 \
  mt7986a-zyxel-ex5700 zyxel,ex5700

fur_dts="$DTS_DIR/mt7981-honor-fur-602.dts"
grep -Fq 'compatible = "mediatek,mt7531"' "$fur_dts" || fail "FUR602 未使用 MT7531 DSA"
grep -Fq 'mtketh-wan = "wan";' "$fur_dts" || fail "FUR602 缺少 DSA HNAT WAN"
grep -Fq 'mtketh-lan = "lan";' "$fur_dts" || fail "FUR602 缺少 DSA HNAT LAN"
grep -Fq 'mtketh-max-gmac = <1>;' "$fur_dts" || fail "FUR602 HNAT GMAC 数量错误"
! grep -Fq 'mediatek,mt753x' "$fur_dts" || fail "FUR602 仍包含旧 GSW 节点"
! grep -Fq '&gsw' "$fur_dts" || fail "FUR602 仍引用旧 GSW 节点"
case_block_has "$MT7981_NETWORK" $'\t*honor,fur-602*)' \
  'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan' || \
  fail "FUR602 的 LAN/WAN DSA 配置缺失"
grep -Fq '*honor,fur-602*' "$MT7981_UPGRADE" || fail "FUR602 缺少 sysupgrade 处理"

dts_node_has "$fur_dts" 'port@0' 'label = "wan";' || fail "FUR602 端口 0 不是 WAN"
dts_node_has "$fur_dts" 'port@1' 'label = "lan3";' || fail "FUR602 端口 1 不是 LAN3"
dts_node_has "$fur_dts" 'port@2' 'label = "lan2";' || fail "FUR602 端口 2 不是 LAN2"
dts_node_has "$fur_dts" 'port@3' 'label = "lan1";' || fail "FUR602 端口 3 不是 LAN1"
dts_node_has "$fur_dts" 'port@6' 'ethernet = <&gmac0>;' || fail "FUR602 CPU 端口不是 MT7531 P6"
grep -Fq 'reg = <0x580000 0x7200000>;' "$fur_dts" || fail "FUR602 UBI 分区布局错误"

device_block_has "$MT7981_IMAGE" honor_fur-602 'IMAGE_SIZE := 116736k' || \
  fail "FUR602 IMAGE_SIZE 与 0x7200000 UBI 分区不一致"
device_block_has "$MT7981_IMAGE" ikuai_q3000 'IMAGE_SIZE := 65536k' || \
  fail "iKuai Q3000 IMAGE_SIZE 与 0x4000000 UBI 分区不一致"
grep -Fq 'reg = <0x580000 0x4000000>;' "$DTS_DIR/mt7981-ikuai-q3000.dts" || \
  fail "iKuai Q3000 UBI 分区布局错误"
device_block_has "$MT7981_IMAGE" ruijie_rg-x30e 'IMAGE_SIZE := 114176k' || \
  fail "RG-X30E IMAGE_SIZE 与普通布局不一致"
device_block_has "$MT7981_IMAGE" ruijie_rg-x30e-pro 'IMAGE_SIZE := 114176k' || \
  fail "RG-X30E Pro IMAGE_SIZE 与普通布局不一致"
grep -Fq 'reg = <0x880000 0x6F80000>;' "$DTS_DIR/mt7981-ruijie-rg-x30e.dts" || \
  fail "RG-X30E 普通布局的 UBI 分区错误"
grep -Fq 'reg = <0x880000 0x6F80000>;' "$DTS_DIR/mt7981-ruijie-rg-x30e-pro.dts" || \
  fail "RG-X30E Pro 普通布局的 UBI 分区错误"

for profile in \
  ruijie_rg-x30e-firmware2 ruijie_rg-x30e-stock \
  ruijie_rg-x30e-pro-firmware2 ruijie_rg-x30e-pro-stock; do
  device_block_has "$MT7981_IMAGE" "$profile" 'IMAGE_SIZE := 35328k' || \
    fail "$profile 的 IMAGE_SIZE 与 0x2280000 UBI 分区不一致"
done

for dts in \
  mt7981-ruijie-rg-x30e-stock.dts mt7981-ruijie-rg-x30e-firmware2.dts \
  mt7981-ruijie-rg-x30e-pro-stock.dts mt7981-ruijie-rg-x30e-pro-firmware2.dts; do
  grep -Fq '0x2280000>;' "$DTS_DIR/$dts" || fail "$dts 的小 UBI 分区大小错误"
done

grep -Fq 'lan) ipad=${ipaddr:-"192.168.1.1"}' \
  "$OPENWRT_DIR/package/base-files/files/bin/config_generate" || \
  fail "默认 LAN 地址不是 192.168.1.1"

echo "23.05 新增设备适配校验通过。"
