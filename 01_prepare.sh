#!/usr/bin/env bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use default ImmortalWrt feeds. The 23.05 MT798x tree already contains the
# matching passwall/xray/sing-box/tailscale package set.
./scripts/feeds update -a

# Apply local 23.05-style adaptations first, then enable the selected profiles.
bash "$WRAPPER_DIR/scripts/apply_2305_adapted_devices.sh" "$PWD"
bash "$WRAPPER_DIR/scripts/enable_2305_existing_devices.sh" "$PWD"

# Argon theme.
rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

# SCUT client.
rm -rf feeds/luci/applications/luci-app-scutclient
git clone https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient

# SCUT Unicom helper.
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 \
  https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile \
  -O package/scut-unicom/Makefile

# LuCI interface for tailscale; tailscale itself comes from the default feed.
rm -rf package/luci-app-tailscale
git clone --depth=1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

./scripts/feeds install -a

# Add disabled Unicom accelerator hint to rc.local.
if ! grep -q 'scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local; then
  sed -i '/^exit 0/i # If you use the Unicom accelerator, remove the leading # and fill in the values below.\n#sleep 10 && /usr/share/scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local
fi

# Set ttyd to default root login.
sed -i "s#option command '/bin/login'#option command '/bin/login -f root'#" feeds/packages/utils/ttyd/files/ttyd.config

# Keep passwall compatibility with trojan-go-only package sets.
if ! grep -q '/usr/bin/trojan-go' package/emortal/default-settings/files/99-default-settings; then
  sed -i "s#exit 0#[ ! -f '/usr/sbin/trojan' ] \\&\\& [ -f '/usr/bin/trojan-go' ] \\&\\& ln -sf /usr/bin/trojan-go /usr/bin/trojan\\nexit 0#" package/emortal/default-settings/files/99-default-settings
fi
