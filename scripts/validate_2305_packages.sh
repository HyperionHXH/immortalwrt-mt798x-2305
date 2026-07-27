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
require_enabled iptables
require_enabled iptables-mod-ipopt

tc_provider="$(find_enabled tc tc-tiny tc-full || true)"
[ -n "$tc_provider" ] || fail "缺少 tc、tc-tiny 或 tc-full"

# 保留 MTK Easy QoS 供用户选择，但不要与 SQM 同时在同一接口启用。
require_enabled luci-app-eqos-mtk

require_disabled luci-app-tailscale
require_disabled tailscale

echo "23.05 软件包校验通过：已加入 SQM（tc provider: $tc_provider），已移除 Tailscale。"
