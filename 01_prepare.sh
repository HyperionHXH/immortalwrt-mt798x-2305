#!/bin/bash
set -e -o pipefail

# Use default immortalwrt feeds only (openwrt-23.05 has passwall/xray/sing-box/tailscale built-in)

./scripts/feeds update -a

# Clone luci-theme-argon from source (jerrykuku)
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

# Clone scutclient
rm -rf feeds/luci/applications/luci-app-scutclient/
git clone https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient

# Clone scut-unicom
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile -O package/scut-unicom/Makefile

# Clone luci-app-tailscale (LuCI interface, depends on tailscale from default feed)
git clone --depth=1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

./scripts/feeds install -a

# Add Unicom accelerator hints to rc.local
sed -i '/^exit 0/i #如果使用联通加速，删除前面的#，并填充后面的值\n#sleep 10 && /usr/share/scut_unicom/add_route.sh server_ip username password' package/base-files/files/etc/rc.local

# Set ttyd to default root login
sed -i "s/option command '\/bin\/login'/option command '\/bin\/login -f root'/" feeds/packages/utils/ttyd/files/ttyd.config

sed -i "s/exit 0/[ ! -f '\/usr\/sbin\/trojan' ] \&\& [ -f '\/usr\/bin\/trojan-go' ] \&\& ln -sf \/usr\/bin\/trojan-go \/usr\/bin\/trojan\nexit 0/" package/emortal/default-settings/files/99-default-settings
