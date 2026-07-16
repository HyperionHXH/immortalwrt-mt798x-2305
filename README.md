# ImmortalWrt MT798x 23.05 固件编译

这是当前已验证可用的 MT798x 23.05 自用固件编译仓库，用来编译带 SCUT、Passwall、OpenClash、Tailscale 等插件的 ImmortalWrt 固件。

- 源码仓库：`padavanonly/immortalwrt-mt798x-6.6`
- 源码分支：`openwrt-23.05`
- 已审查源码提交：`8fd3008be125e590664b311e3aaedee344adc354`
- 本地旧 WSL 路径：`/home/miunah/my_project/mt798x_build`
- 当前策略：本地不再保留完整源码和编译目录，主要通过 GitHub Actions 手动编译

## 设备变种

完整设备支持审计见 [SUPPORTED_DEVICES_23_05.md](SUPPORTED_DEVICES_23_05.md)。

| 变种 | 平台 | 示例设备 |
|---|---|---|
| `mt7981-ax3000` | mt7981 | RAX3000M、ASR3000、CT3003、JCG Q30、360 T7、GL-MT3000、AX3000T、Routerich AX3000 |
| `mt7986-ax4200` | mt7986 | BPI-R3 Mini、BPI-R3 Mini 110M |
| `mt7986-ax6000` | mt7986 | GL-MT6000、Netcore N60、JDCloud RE-CP-03、Ruijie RG-X60 Pro、Zyxel EX5700 |
| `mt7986-ax6000-256m` | mt7986 | 256 MB 内存版本 |

这个 wrapper 当前会启用 53 个面向用户的设备 profile：

- 38 个是 23.05 源码树里已经存在、只是原 defconfig 没全选的设备；
- 另外 15 个通过 `patches/2305/` 做了 23.05 风格适配，包括 `cmcc_xr30`、`cmcc_xr30-emmc`、`honor_fur-602`、`ikuai_q3000`、`newland_nl-wr8103`、`newland_nl-wr9103`、`routerich_ax3000`、6 个 `ruijie_rg-x30e*` 布局、`ruijie-rg-x60-pro-stock` 和 `zyxel_ex5700`。

21.02 只作为“曾经支持过哪些设备”的名称参考，不直接照搬旧代码。实际实现仍以 23.05 源码结构为准。

## GitHub Actions 编译

Actions 只允许手动触发，不会因为 push 自动开始编译。

入口：

[MT798x 23.05 手动编译](https://github.com/HyperionHXH/immortalwrt-mt798x-2305/actions/workflows/mt798x.yml)

点 **Run workflow** 后会编译 4 个变种：

- `mt7981-ax3000`
- `mt7986-ax4200`
- `mt7986-ax6000-256m`
- `mt7986-ax6000`

## 本地编译参考

现在不建议再把完整源码长期放在 WSL 里。下面命令只作为以后需要本地复现问题时的参考。

```bash
cd /home/miunah/my_project/mt798x_build/openwrt
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
export GOPROXY="https://goproxy.cn,direct"

bash ../01_prepare.sh
cat defconfig/mt7981-ax3000.config > .config
bash ../02_add_package.sh
make defconfig
make download -j8
make -j2
```

全量编译参考：

```bash
cd /home/miunah/my_project/mt798x_build
JOBS=2 bash build_all.sh
```

`build_all.sh` 会先执行 `01_prepare.sh`，所以 feeds 会先刷新并链接好，然后才生成 `.config`。`01_prepare.sh` 也会自动应用本仓库的 23.05 设备适配并启用选定设备 profile。适配脚本是幂等的，重复运行不会重复插入同一段配置。

feeds 刷新是必须的，因为 `luci`、`lua-cjson` 等依赖会影响 `default-settings`、`default-settings-chn` 和 `mtwifi-cfg` 是否能正确选中。

本仓库会把上游 23.05 的普通 LAN 默认地址从 `192.168.6.1` 明确改为 `192.168.1.1`。Action 会在编译前运行设备适配校验，分区上限、FUR602 DSA/HNAT 或默认地址不符合预期时直接停止。

Action 会核对 23.05 源码提交。上游分支移动后必须先重新审查并更新固定提交，旧补丁不会直接套到未审查的新源码上。

## Wi-Fi 状态

当前 23.05 可用路线是：

- 必须保留 `openwrt/package/base-files/files/sbin/wifi`；
- defconfig 使用 `kmod-mt_wifi`、`mtwifi-cfg`、`luci-app-mtwifi-cfg` 和 `wifi-dats`；
- 不启用 `wifi-profile`；
- 不启用旧的 `luci-app-mtk`；
- `mtwifi-cfg` 提供 `/etc/hotplug.d/net/10-mtwifi-detect`、`/lib/wifi/mtwifi.sh` 和 `/lib/netifd/wireless/mtwifi.sh`。

不要删除 `/sbin/wifi`。以前 CI 里删除 `/sbin/wifi` 的做法属于另一条 `luci-app-mtk + wifi-profile` 实验路线，不适用于当前这个已验证的 23.05 路线。

## 已知可用插件

用户之前反馈 23.05 固件可用，插件集合包括：

- scutclient
- Passwall / Xray / Hysteria / Sing-Box
- OpenClash
- Tailscale
- Argon 主题
- USB 存储相关模块
- block-mount

## WSL 注意事项

如果以后必须本地编译，源码和构建目录要放在 WSL 文件系统里，不要放在 `/mnt/c`。

```bash
sudo tee -a /etc/wsl.conf <<'EOF'
[interop]
appendWindowsPath=false
EOF
```
