#!/usr/bin/env bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"

# 使用 ImmortalWrt 默认 feeds。23.05 MT798x 源码树里已经带有匹配的
# passwall/xray/sing-box/tailscale 包集合。
./scripts/feeds update -a

# 先应用本地 23.05 风格设备适配，再启用选中的设备 profile。
bash "$WRAPPER_DIR/scripts/apply_2305_adapted_devices.sh" "$PWD"
bash "$WRAPPER_DIR/scripts/enable_2305_existing_devices.sh" "$PWD"

# Argon 主题。
rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

# SCUT 校园网客户端。
rm -rf feeds/luci/applications/luci-app-scutclient
git clone https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient

# SCUT 联通辅助脚本。
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 \
  https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile \
  -O package/scut-unicom/Makefile

# tailscale 的 LuCI 界面；tailscale 本体来自默认 feed。
rm -rf package/luci-app-tailscale
git clone --depth=1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

./scripts/feeds install -a

# 该 23.05 分支把普通 LAN 默认地址改成了 192.168.6.1。本仓库统一使用
# 192.168.1.1，避免刷机后按常用地址排查时误判设备未启动。
sed -i 's/192\.168\.6\.1/192.168.1.1/' \
  package/base-files/files/bin/config_generate
grep -Fq 'lan) ipad=${ipaddr:-"192.168.1.1"}' package/base-files/files/bin/config_generate

# 在 rc.local 中加入默认禁用的联通加速提示。
if ! grep -q 'scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local; then
  sed -i '/^exit 0/i # 如果要使用联通加速，删除下一行开头的 # 并填好参数。\n#sleep 10 && /usr/share/scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local
fi

# 设置 ttyd 默认以 root 登录。
sed -i "s#option command '/bin/login'#option command '/bin/login -f root'#" feeds/packages/utils/ttyd/files/ttyd.config

# 兼容只安装 trojan-go 的 passwall 包集合。
if ! grep -q '/usr/bin/trojan-go' package/emortal/default-settings/files/99-default-settings; then
  sed -i "s#exit 0#[ ! -f '/usr/sbin/trojan' ] \\&\\& [ -f '/usr/bin/trojan-go' ] \\&\\& ln -sf /usr/bin/trojan-go /usr/bin/trojan\\nexit 0#" package/emortal/default-settings/files/99-default-settings
fi
