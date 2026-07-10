# MT798x 23.05 设备支持审计

检查日期：2026-07-05。

## 适配原则

实现以 23.05 源码树为基准。21.02 只用来确认“以前出现过哪些设备名称”，不能直接照搬旧的 21.02 DTS、镜像规则或平台脚本。

缺失设备必须按 23.05 的源码结构重新适配，然后再验证。

## 来源

- 23.05 源码：`padavanonly/immortalwrt-mt798x-6.6`，分支 `openwrt-23.05`
- 21.02 名称参考：`hanwckf/immortalwrt-mt798x`，分支 `openwrt-21.02`
- 本地旧编译 wrapper：`/home/miunah/my_project/mt798x_build`

## 总结

| 来源 | 设备定义数 | defconfig 覆盖设备数 |
|---|---:|---:|
| 21.02 名称参考 | 91 | 47 |
| 本 wrapper 修改前的 23.05 源码 | 76 | 25 |
| 运行 `scripts/enable_2305_existing_devices.sh` 后的 23.05 wrapper | 76 | 38 |
| 应用 `patches/2305/` 适配后的 23.05 wrapper | 91 | 53 |

注意：`imou_lc-hx3001` 在 23.05 源码里本来就存在，并且已经由 `defconfig/mt7981-ax3000.config` 选中。

## 23.05 Defconfig 已覆盖设备

运行 `scripts/apply_2305_adapted_devices.sh` 和 `scripts/enable_2305_existing_devices.sh` 后，本 wrapper 会选中下面这些设备。属于“本 wrapper 适配进 23.05”的设备见后面的“本 wrapper 新增适配”一节。

```text
BPI-R3MINI-EMMC
BPI-R3MINI-NAND
BPI-R3MINI-NAND-110M
abt_asr3000
cetron_ct3003
cmcc_a10
cmcc_rax3000m
cmcc_rax3000m-emmc
cmcc_xr30
cmcc_xr30-emmc
glinet_gl-mt2500
glinet_gl-mt3000
glinet_gl-mt6000
glinet_gl-x3000
glinet_gl-xe3000
h3c_nx30pro
honor_fur-602
imou_lc-hx3001
ikuai_q3000
jcg_q30
jdcloud_re-cp-03
konka_komi-a31
livinet_zr-3020
mt7981-360-t7
mt7981-360-t7-108M
mt7981-clt-r30b1
mt7981-clt-r30b1-112M
newland_nl-wr8103
newland_nl-wr9103
netcore_n60
nokia_ea0326gmp
nradio_wt9103
nradio_wt9103_512m
one_r35-mini
routerich_ax3000
ruijie_rg-x30e
ruijie_rg-x30e-firmware2
ruijie_rg-x30e-pro
ruijie_rg-x30e-pro-firmware2
ruijie_rg-x30e-pro-stock
ruijie_rg-x30e-stock
ruijie-rg-x60-pro
ruijie-rg-x60-pro-stock
ruijie-rg-x60-pro-uboot
tplink_tl-xdr6086
tplink_tl-xdr6088
xiaomi_mi-router-ax3000t
xiaomi_mi-router-ax3000t-stock
xiaomi_mi-router-wr30u-112m
xiaomi_mi-router-wr30u-stock
xiaomi_redmi-router-ax6000
xiaomi_redmi-router-ax6000-stock
zyxel_ex5700
```

## 23.05 源码中存在但未启用

下面这些 profile 在 23.05 源码里存在，但本 wrapper 没有选中。原因通常是它们属于参考板、底层存储布局变体、共享模板，或者不适合作为普通用户直接刷写的固件产物。

```text
mediatek_mt7986-fpga
mediatek_mt7986-fpga-ubi
mt7981-emmc-rfb
mt7981-fpga-emmc
mt7981-fpga-sd
mt7981-fpga-snfi-nand
mt7981-fpga-spim-nand
mt7981-fpga-spim-nor
mt7981-sd-rfb
mt7981-snfi-nand-2500wan-p5
mt7981-spim-nand-2500wan-gmac2
mt7981-spim-nand-gsw
mt7981-spim-nand-rfb
mt7981-spim-nor-rfb
mt7986a-ax6000-2500wan-gsw-spim-nand-rfb
mt7986a-ax6000-2500wan-sd-rfb
mt7986a-ax6000-2500wan-spim-nand-rfb
mt7986a-ax6000-2500wan-spim-nor-rfb
mt7986a-ax6000-emmc-rfb
mt7986a-ax6000-snfi-nand-rfb
mt7986a-ax6000-spim-nand-rfb
mt7986a-ax6000-spim-nor-rfb
mt7986a-ax7800-2500wan-spim-nand-rfb
mt7986a-ax7800-2500wan-spim-nor-rfb
mt7986a-ax7800-spim-nand-rfb
mt7986a-ax7800-spim-nor-rfb
mt7986a-ax8400-2500wan-spim-nand-rfb
mt7986a-ax8400-spim-nand-rfb
mt7986b-ax6000-2500wan-gsw-spim-nand-rfb
mt7986b-ax6000-2500wan-sd-rfb
mt7986b-ax6000-2500wan-snfi-nand-rfb
mt7986b-ax6000-2500wan-spim-nand-rfb
mt7986b-ax6000-2500wan-spim-nor-rfb
mt7986b-ax6000-emmc-rfb
mt7986b-ax6000-snfi-nand-rfb
mt7986b-ax6000-spim-nand-rfb
mt7986b-ax6000-spim-nor-rfb
tplink_tl-common
```

## 本 wrapper 新增适配

下面这些设备通过 `patches/2305/` 下的 23.05 风格补丁加入，并由 wrapper 在补丁应用后选中。

```text
cmcc_xr30
cmcc_xr30-emmc
honor_fur-602
ikuai_q3000
newland_nl-wr8103
newland_nl-wr9103
routerich_ax3000
ruijie_rg-x30e
ruijie_rg-x30e-firmware2
ruijie_rg-x30e-pro
ruijie_rg-x30e-pro-firmware2
ruijie_rg-x30e-pro-stock
ruijie_rg-x30e-stock
ruijie-rg-x60-pro-stock
zyxel_ex5700
```

说明：

- `cmcc_xr30` 和 `cmcc_xr30-emmc` 按 RAX3000M 系列设备处理，使用 23.05 的 DSA 交换机布局，不沿用 21.02 的旧 `gsw` 写法。
- `cmcc_xr30-emmc` 有自己的 MAC 偏移处理，不会改动现有 `cmcc_rax3000m-emmc` 的偏移。
- 增加 XR30 eMMC 时，同时把 eMMC 校准 preinit 匹配从过时的 `cmcc,rax3000m-em` 修正为 `cmcc,rax3000m-emmc`。
- `ikuai_q3000` 从 21.02 的 DSA 风格板级描述适配而来，并改成 23.05 可用的 SPI bus-width 属性和当前 base-files 放置方式。
- `honor_fur-602` 已从 21.02 的旧 `gsw` 写法改成 23.05 风格的 DSA/`mt7531` 交换机描述，LAN/WAN 由 `lan1 lan2 lan3` 和 `wan` 生成。旧版实机表现为常绿但无法访问 `192.168.1.1`，高度怀疑是旧 `eth0.1`/`eth0.2` 网络布局不适合 23.05。
- `newland_nl-wr8103`、`newland_nl-wr9103` 和 `routerich_ax3000` 仍从 21.02 的 MT7981 `gsw` 设备描述适配而来。当前 23.05 源码的 mt7981 内核配置仍启用旧 `MT753X_GSW` 驱动，所以这条路线在结构上是可编译的，但仍需实机验证。
- `routerich_ax3000` 会把 5 GHz Wi-Fi MAC 写入当前 23.05 的 `mt7981.dbdc.b1.dat` 路径，不再依赖旧的 `l1dat if2dat` 辅助路径。
- `ruijie_rg-x30e*` 适配为 6 个 DSA 布局：RG-X30E 和 RG-X30E Pro 各自的普通、stock、firmware2 版本。Wi-Fi MAC 处理直接写当前 23.05 的 MT7981 dat 文件，不再依赖旧的 `l1dat if2dat` 路径。
- `ruijie-rg-x60-pro-stock` 复用 23.05 已有的 `mt7986a-ruijie-rg-x60-pro.dtsi` 硬件描述，以及现有 `ruijie,rg-x60-pro*` 的网络、MAC 和 sysupgrade base-files 处理。
- stock profile 有自己的 compatible 字符串 `ruijie,rg-x60-pro-stock`，没有继承 21.02 里的旧 compatible 拼写问题。
- `zyxel_ex5700` 是从适配 21.02/5.4 内核的 EX5700 DTS 迁移而来，没有改用更新的 mainline `ex5700-telenor` DTS，因为这个 23.05 构建仍然针对 5.4 内核树。
- 这里完成的是“源码结构层面适配”。真实设备的启动、以太网、Wi-Fi、LuCI、sysupgrade、重置键、LED、MAC 地址等仍需要实机验证后，才能算完全确认。

## 21.02 有而 23.05 仍缺失的设备

下面这两个设备是 21.02 看起来更“多”的主要差异。它们没有在已检查的 23.05 源码树中实现，需要单独做真正的 23.05 风格适配后才能加入构建。

```text
xiaomi_mi-router-ax3000t-an8855
xiaomi_mi-router-ax3000t-an8855-stock
```

`xiaomi_mi-router-ax3000t-an8855*` 目前故意不启用。21.02 源码里包含 `airoha/an8855` 交换机驱动，以及这个硬件对应的 Xiaomi 共享 DTSI 节点；但已检查的 23.05 源码没有 AN8855 驱动，也没有 `gsw_an8855` 节点。只添加两个 DTS/profile 文件很可能会产出以太网不可用的误导性固件，所以这里需要单独做 AN8855 驱动移植任务。

## 后续适配规则

每个缺失设备都要按 23.05 来实现：

- DTS/DTSI 使用当前 23.05 内核树风格；
- 镜像规则放在 `target/linux/mediatek/image/mt7981.mk` 或 `mt7986.mk`；
- DSA 网络布局、LED 默认值、MAC 推导、Wi-Fi 校准和 sysupgrade 处理使用当前 23.05 base-files 风格；
- 设备包和存储布局必须匹配真实硬件；
- 只有 23.05 recipe 已存在后，才能加入 defconfig 选择；
- 先做编译测试，再做真实设备启动、以太网、Wi-Fi、LuCI、重置键、LED、MAC 地址和 sysupgrade 测试。

专门的设备维护仓库应该保存这些 23.05 风格适配补丁。这个自用固件仓库只消费已经整理好的设备支持，并叠加 SCUT 插件集合来编译固件。
