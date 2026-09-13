#!/usr/bin/env bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"
SCUTCLIENT_COMMIT="d9d618be97870813252b5ce7540f6a4ea4c22ab0"
DOWNLOAD_PATCH="$WRAPPER_DIR/patches/2305/build-system/download-reliability.patch"

if git apply --reverse --check "$DOWNLOAD_PATCH" >/dev/null 2>&1; then
  echo "下载器可靠性补丁已经应用。"
elif git apply --check "$DOWNLOAD_PATCH"; then
  git apply "$DOWNLOAD_PATCH"
  echo "已应用下载器可靠性补丁。"
else
  echo "错误：下载器可靠性补丁与当前源码不匹配。" >&2
  exit 1
fi

# 默认关闭 dnsmasq 的重绑定保护（LuCI 的"重绑定保护"开关）。
REBIND_PATCH="$WRAPPER_DIR/patches/2305/build-system/dnsmasq-no-rebind.patch"
if git apply --reverse --check "$REBIND_PATCH" >/dev/null 2>&1; then
  echo "dnsmasq 重绑定保护补丁已经应用。"
elif git apply --check "$REBIND_PATCH"; then
  git apply "$REBIND_PATCH"
  echo "已应用 dnsmasq 重绑定保护补丁。"
else
  echo "错误：dnsmasq 重绑定保护补丁与当前源码不匹配。" >&2
  exit 1
fi

# 使用 ImmortalWrt 默认 feeds。23.05 MT798x 源码树里已经带有匹配的
# passwall/xray/sing-box 包集合。
./scripts/feeds update -a

# ---- golang 工具链升级到 1.27（新版 passwall 核心需要）----
# 23.05 feed 的 golang（1.21）用 go1.4→go1.17 两级自举编目标版本，
# go1.17 编不了 Go 1.27。这里保持 23.05 原生单包结构，只改版本数据，
# 并把"编目标版本"的引导换成官方预编译 go1.24.13（ImmortalWrt master
# 官方给 Go 1.27 配对的 bootstrap 版本），跳过整条自举链。
# 注意：必须在 feeds update 之后执行，否则改动会被 update 重建的 feeds 覆盖。
echo ">> 升级 feeds/packages/lang/golang 到 Go 1.27 ..."
sed -i \
  -e 's/^GO_VERSION_MAJOR_MINOR:=1.21/GO_VERSION_MAJOR_MINOR:=1.27/' \
  -e 's/^GO_VERSION_PATCH:=13/GO_VERSION_PATCH:=0/' \
  -e 's|^PKG_HASH:=.*|PKG_HASH:=7002403d7cc44529ef6d26f69a44818263395ead7c16c05a5808ae047ebeb0e5|' \
  feeds/packages/lang/golang/golang/Makefile
# 目标版本的 GOROOT_BOOTSTRAP 从硬编码的 go1.17 目录改为 BOOTSTRAP_ROOT_DIR
# （设置了 CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT 时即外部预编译工具链）
sed -i 's/GOROOT_BOOTSTRAP="$(BOOTSTRAP_1_17_BUILD_DIR)"/GOROOT_BOOTSTRAP="$(BOOTSTRAP_ROOT_DIR)"/' \
  feeds/packages/lang/golang/golang/Makefile
grep -n "GO_VERSION_MAJOR_MINOR\|GOROOT_BOOTSTRAP" feeds/packages/lang/golang/golang/Makefile | head -4

boot_dir="$(pwd)/.go-bootstrap-prebuilt"
if [ ! -x "$boot_dir/bin/go" ]; then
  rm -rf "$boot_dir"; mkdir -p "$boot_dir"
  wget --tries=5 --timeout=30 -O /tmp/go-bootstrap.tgz \
    https://mirrors.ustc.edu.cn/golang/go1.24.13.linux-amd64.tar.gz \
  || wget --tries=5 --timeout=30 -O /tmp/go-bootstrap.tgz \
    https://go.dev/dl/go1.24.13.linux-amd64.tar.gz
  tar -xzf /tmp/go-bootstrap.tgz -C "$boot_dir" --strip-components=1
  rm -f /tmp/go-bootstrap.tgz
fi
"$boot_dir/bin/go" version

# 把外部 bootstrap 路径写进源码树各 defconfig，make 时随 .config 生效
for golang_cfg in defconfig/*.config; do
  [ -f "$golang_cfg" ] || continue
  sed -i '/^CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=/d' "$golang_cfg"
  printf 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="%s"\n' "$boot_dir" >> "$golang_cfg"
done

# ---- passwall 全家桶改为编译时拉取上游最新版 ----
# 23.05 feeds 里的 passwall 核心组件已被冻结（xray 停在 24.12.31、
# sing-box 停在 1.11.15）。golang 工具链已在上面升级到 1.27，
# 这里删除 feed 里冻结的核心组件，改用 xiaorouji/openwrt-passwall-packages
# main 分支；luci-app-passwall 用 immortalwrt/luci openwrt-25.12 分支
# （26.x，23.05 feed 冻结在 25.8.5）。
echo ">> 删除 feeds 里冻结的 passwall 核心组件（改用上游 main 分支）..."
for pw_pkg in chinadns-ng dns2socks geoview hysteria ipt2socks microsocks naiveproxy \
              shadow-tls shadowsocks-rust shadowsocksr-libev simple-obfs sing-box tcping \
              v2ray-geodata v2ray-plugin xray-core xray-plugin; do
  rm -rf "feeds/packages/net/$pw_pkg"
done

echo ">> 克隆 xiaorouji/openwrt-passwall-packages (main) ..."
rm -rf package/passwall-packages
git clone --depth=1 -b main \
  https://github.com/xiaorouji/openwrt-passwall-packages.git package/passwall-packages

echo ">> 用 luci feed 25.12 的 luci-app-passwall (26.x) 替换 23.05 冻结版 ..."
luci_tmp="$(mktemp -d)"
git clone --depth=1 -b openwrt-25.12 --filter=blob:none --sparse \
  https://github.com/immortalwrt/luci.git "$luci_tmp/luci"
git -C "$luci_tmp/luci" sparse-checkout set applications/luci-app-passwall
# 注意：必须放回 luci feed 内部（feeds/luci/applications/...）。
# 应用 Makefile 用 `include ../../luci.mk` 引用 feed 根的构建模板，
# 复制到 package/ 下会让相对路径断裂、包被 make 静默丢弃。
rm -rf feeds/luci/applications/luci-app-passwall
cp -a "$luci_tmp/luci/applications/luci-app-passwall" feeds/luci/applications/luci-app-passwall
rm -rf "$luci_tmp"

# 先应用本地 23.05 风格设备适配，再启用选中的设备 profile。
bash "$WRAPPER_DIR/scripts/apply_2305_adapted_devices.sh" "$PWD"
bash "$WRAPPER_DIR/scripts/enable_2305_existing_devices.sh" "$PWD"

# Argon 主题。
rm -rf package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon

# SCUT 校园网客户端。
rm -rf feeds/luci/applications/luci-app-scutclient
git clone https://github.com/hanwckf/luci-app-scutclient.git feeds/luci/applications/luci-app-scutclient
git -C feeds/luci/applications/luci-app-scutclient checkout --detach "$SCUTCLIENT_COMMIT"
[ "$(git -C feeds/luci/applications/luci-app-scutclient rev-parse HEAD)" = "$SCUTCLIENT_COMMIT" ]
git -C feeds/luci/applications/luci-app-scutclient apply \
  "$WRAPPER_DIR/patches/2305/packages/luci-app-scutclient-ucodebridge.patch"
grep -Fq 'local fs = require "nixio.fs"' \
  feeds/luci/applications/luci-app-scutclient/luasrc/controller/scutclient.lua

# SCUT 联通辅助脚本。
mkdir -p package/scut-unicom
wget --tries=5 --timeout=30 \
  https://raw.githubusercontent.com/wykdg/route_script/master/scut-unicom/Makefile \
  -O package/scut-unicom/Makefile

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
