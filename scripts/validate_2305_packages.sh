#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-.config}"

fail() {
  echo "软件包校验失败：$*" >&2
  exit 1
}

require_enabled() {
  grep -Fqx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE" || fail "缺少 $1"
}

require_disabled() {
  ! grep -Fqx "CONFIG_PACKAGE_$1=y" "$CONFIG_FILE" || fail "$1 不应被选中"
  ! grep -Fqx "CONFIG_PACKAGE_$1=m" "$CONFIG_FILE" || fail "$1 不应被选中"
}

find_enabled() {
  local package

  for package in "$@"; do
    if grep -Fqx "CONFIG_PACKAGE_$package=y" "$CONFIG_FILE"; then
      printf '%s\n' "$package"
      return 0
    fi
  done

  return 1
}

[ -f "$CONFIG_FILE" ] || fail "缺少配置文件 $CONFIG_FILE"

# SQM 的运行依赖应由 luci-app-sqm 自动带入。
require_enabled luci-app-sqm
require_enabled sqm-scripts
require_enabled kmod-sched-cake
require_enabled kmod-ifb
require_enabled iptables-mod-ipopt

tc_provider="$(find_enabled tc tc-tiny tc-full || true)"
[ -n "$tc_provider" ] || fail "缺少 tc、tc-tiny 或 tc-full"

iptables_provider="$(find_enabled iptables iptables-nft iptables-legacy || true)"
[ -n "$iptables_provider" ] || fail "缺少 iptables、iptables-nft 或 iptables-legacy"

# 保留 MTK Easy QoS 供用户选择，但不要与 SQM 同时在同一接口启用。
require_enabled luci-app-eqos-mtk

require_disabled luci-app-tailscale
require_disabled tailscale

# passwall 套件必须完整选中，防止 luci.mk 链路断裂之类的问题导致包被静默丢弃。
require_enabled luci-app-passwall
require_enabled chinadns-ng
require_enabled xray-core
require_enabled sing-box
require_enabled hysteria
require_enabled geoview

# package.conf 里每一行都必须真的生效。02_add_package.sh 会把每行写成
# CONFIG_PACKAGE_<line>=y，而包名写错、包不存在、或者混进一条残留的 CONFIG_ 行，
# make defconfig 都会静默丢掉它 —— 固件里就少了东西却没人知道。
# （2026-09-22 就是这么发现 socat 和 wireguard 从来没进过镜像的。）
PACKAGE_CONF="${PACKAGE_CONF:-$(dirname "$0")/../package.conf}"
if [ -f "$PACKAGE_CONF" ]; then
  missing_lines=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    grep -Fqx "CONFIG_PACKAGE_${line}=y" "$CONFIG_FILE" || missing_lines+=("$line")
  done < "$PACKAGE_CONF"

  if [ "${#missing_lines[@]}" -gt 0 ]; then
    echo "package.conf 中这些条目没有生效（包名不存在/写错/残留的 CONFIG_ 行）：" >&2
    printf '  - %s\n' "${missing_lines[@]}" >&2
    fail "package.conf 有 ${#missing_lines[@]} 条无效条目"
  fi
  echo "package.conf 的条目全部生效（$(grep -cvE '^[[:space:]]*(#|$)' "$PACKAGE_CONF") 条）。"
fi

echo "23.05 软件包校验通过：已加入 SQM（tc: $tc_provider，iptables: $iptables_provider），已移除 Tailscale，passwall 套件完整。"
