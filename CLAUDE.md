# CLAUDE.md — ImmortalWrt MT798x 23.05 Build

## 项目概述

为 MT798x 路由器编译 ImmortalWrt 23.05 固件（含 scutclient、passwall、openclash 等）。
源码: `padavanonly/immortalwrt-mt798x-6.6` (openwrt-23.05 分支)

## 目录结构

```
/home/miunah/my_project/mt798x_build/
├── build_all.sh          # 全量编译 4 变种脚本
├── 01_prepare.sh         # feeds 配置 (源文件在 scripts/)
├── 02_add_package.sh     # 从 package.conf 生成 .config
├── package.conf          # ★ 插件配置文件
├── README.md
├── .gitignore
├── openwrt/              # ImmortalWrt 源码 (238MB, git clone 来的)
├── scripts/              # HyperionHXH/immortalwrt-mt798x-2305 的 git clone
├── artifacts/            # 编译产物
└── .github/workflows/    # CI 配置
```

## 编译命令

```bash
cd /home/miunah/my_project/mt798x_build/openwrt

# 必要环境变量
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
export GOPROXY="https://goproxy.cn,direct"

# 配置 + 编译 (单变种)
cat defconfig/mt7981-ax3000.config > .config
bash ../02_add_package.sh
make defconfig
make download -j8
make -j16

# 全量编译 4 变种
bash ../build_all.sh
```

## 已修改的源文件

### 1. `openwrt/package/base-files/files/bin/config_generate`
- 第165行: `192.168.6.1` → `192.168.1.1`

### 2. `openwrt/feeds/luci/applications/luci-app-scutclient/luasrc/controller/scutclient.lua`
- `require "nixio.fs"` → `local function file_exists()` polyfill
- 所有 `fs.access()` → `file_exists()`
- `fs.mkdirr()` → `os.execute("mkdir -p")`

### 3. `openwrt/package/mtk/applications/luci-app-mtk/luasrc/controller/mtkwifi.lua`
- `require "nixio.fs"` → polyfill (但当前未使用此包)

### 4. `openwrt/package/mtk/applications/luci-app-mtk/root/` 下删除了3个文件
- `root/sbin/l1dat`
- `root/usr/lib/lua/inspect.lua`
- `root/usr/lib/lua/l1dat_parser.lua`
(因为与 mtwifi-cfg 冲突)

### 5. `openwrt/package/mtk/drivers/wifi-profile/Makefile`
- 添加了 `mtkwifi.lua` 的安装行（当前 wifi-profile 未启用，此修改无用）

### 6. `openwrt/package/mtk/drivers/wifi-profile/files/common/mtkwifi.lua`
- 复制自 `luci-app-mtk/root/usr/lib/lua/mtkwifi.lua`（68KB 版，有问题）
- 后来覆盖为 `mtwifi.lua` 的副本（16KB 版）
- ★ 当前 wifi-profile 未启用，此文件实际未使用

### 7. CI 工作流要求的文件删除
- ~~`rm -f openwrt/package/base-files/files/sbin/wifi`~~ **已修复：此文件必须保留！见下方修复说明**
- 原因：原以为 CI (tsingui 等) 需要删除标准 /sbin/wifi，但实际上 CI 用的是 luci-app-mtk + wifi-profile（后者自带 LUA 版 /sbin/wifi）。我们用 mtwifi-cfg（不启用 wifi-profile），必须保留标准 /sbin/wifi。
- 已通过 `git restore package/base-files/files/sbin/wifi` 恢复

## Wi-Fi 问题（★★★ 核心未解决 ★★★）

### 当前状态
WiFi 驱动已加载（`lsmod` 能看到 mt_wifi、ra0 接口存在），但 **LuCI 不显示"网络→无线"菜单**。

### defconfig 原始 WiFi 配置
```
CONFIG_PACKAGE_kmod-mt_wifi=y        # MTK WiFi 内核驱动
CONFIG_PACKAGE_mtwifi-cfg=y          # MTK WiFi 配置工具
CONFIG_PACKAGE_luci-app-mtwifi-cfg=y # MTK WiFi LuCI (JS 面板)
CONFIG_PACKAGE_wifi-dats=y           # WiFi 校准数据 (wifi-profile 的子包)
# CONFIG_PACKAGE_wifi-profile is not set  # 故意禁用的
```

### WiFi 在 23.05 的工作机制（预期）
```
mt_wifi 驱动加载 → hotplug (10-mtwifi-detect)
  → netifd wireless handler (mtwifi.sh)
    → uci wireless config 生成
      → luci-mod-network 显示"网络→无线"菜单
        → luci-app-mtwifi-cfg 的 JS 面板 (wireless-mtk.js)
```

### 尝试过但失败的方案

| 方案 | 结果 | 原因 |
|------|------|------|
| defconfig 默认 + luci-mod-network | 菜单不出现 | uci.wireless.@wifi-device 为空 → 菜单隐藏 |
| +wifi-profile + mtkwifi.lua 补丁 | 菜单出现但崩 | /sbin/wifi 能用但缺 ioctl_helper.so |
| +luci-app-mtk (替换 mtwifi-cfg) | 菜单出现，配置页崩 | nixio.fs → 修了；然后 creat_link_for_nvram nil → 库文件冲突 |
| +luci-app-mtk + 保留 mtwifi-cfg | 菜单出现，wifi detect报错 | mtkwifi.lua 版本不对（68KB vs 16KB） |
| 回到 defconfig 默认 + luci-mod-network | 菜单不出现 | 回到起点 |

### 关键发现
1. `luci-mod-network` 的无线菜单检查 `uci.wireless.@wifi-device`，无设备则隐藏
2. 驱动 ra0 存在但菜单不显示 → hotplug/netifd 没生成 uci wireless 配置
3. `wifi detect` / `wifi up` 需要 wifi-profile 的 /sbin/wifi，但 defconfig 禁用了它
4. `luci-app-mtk`（21.02风格）能让菜单出现，但需要 ioctl_helper.so + mtkwifi.lua (68KB版)
5. `luci-app-mtk` 的 LuCI 模板是旧 .htm 格式，在 23.05 下可能不正常

### 当前 package.conf 配置
```
# Wi-Fi 相关: luci-mod-network (当前方案)
# 未使用: wifi-profile, luci-app-mtk
```
见上方 package.conf 完整内容。

### 可以尝试的方向
- **方向A**: 用 luci-app-mtk + 修复其 68KB mtkwifi.lua 中缺失的 `creat_link_for_nvram` 函数
- **方向B**: 修好 netifd hotplug 让它正确生成 uci wireless 配置（不需要 /sbin/wifi）
- **方向C**: 从 21.02 固件提取完整 WiFi 配置文件，直接写入 23.05
- **方向D**: 找其他成功在 23.05 上使用 MTK WiFi 的项目参考

### ★ 2026-06-06 修复: 恢复 /sbin/wifi

**根因**: `/sbin/wifi` 被删除，但 mtwifi-cfg 不提供替代品。hotplug 链断裂导致 uci wireless 配置无法生成。

**WiFi 配置生成的完整链条**:
```
mt_wifi 驱动加载 → ra0 接口创建
  → hotplug: 10-mtwifi-detect 触发
    → /sbin/wifi config (标准 OpenWrt 脚本, 来自 base-files)
      → include /lib/wifi → 加载 mtwifi.sh
        → detect_mtwifi() 调用 l1util 检测硬件
          → 生成 /etc/config/wireless (uci wireless 配置)
            → netifd 接管 → LuCI 显示"网络→无线"菜单
```

**修复方法**: `git restore openwrt/package/base-files/files/sbin/wifi`

**为什么之前会删除**: CI 工作流 (tsingui 等) 用 luci-app-mtk + wifi-profile 方案，后者自带 LUA 版 /sbin/wifi，需要删除标准版避免冲突。但我们的 defconfig 使用 mtwifi-cfg（不启用 wifi-profile），必须保留标准 /sbin/wifi。

**待验证** (刷机后):
1. `ls -la /sbin/wifi` — 文件存在
2. `/sbin/wifi config` — 手动运行，检查是否生成 /etc/config/wireless
3. `uci show wireless` — 应包含 wifi-device 条目
4. LuCI「网络→无线」菜单应出现

## 其他已解决/正常工作的

- ✅ scutclient 校园网客户端 → 修复了 nixio.fs 兼容性
- ✅ passwall + xray-core + hysteria + sing-box → 全部编译并运行
- ✅ IP: 192.168.1.1
- ✅ argon 主题
- ✅ tailscale
- ✅ openclash
- ✅ USB 存储支持 (kmod-usb-storage, ext4, vfat, exfat, ntfs)
- ✅ block-mount (U盘自动挂载)
- ✅ 编译流程: build_all.sh 一键编译 4 变种

## 编译环境

- WSL2 Ubuntu 24.04, 16 核, 11GB RAM, 1007G 磁盘
- Go 代理: `GOPROXY=https://goproxy.cn,direct`（必需，proxy.golang.org 被墙）
- 清华 apt 镜像已配置
- wsl.conf 已添加 `appendWindowsPath=false`（需重启 WSL 生效）

## GitHub 仓库

- 用户仓库: `HyperionHXH/immortalwrt-mt798x-2305`
- 本地 clone: `scripts/` 目录
- 已 commit 但未 push（网络问题，需通过 Windows 端 push）
- 需要在 Windows 端手动 push: `C:\Users\MiunaH\Desktop\SCUT\immortalwrt-mt798x-2305`
