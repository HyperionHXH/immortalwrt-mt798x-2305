# MT798x 23.05 Device Support Audit

Checked on 2026-07-05.

## Policy

Use 23.05 as the implementation baseline. The 21.02 tree is only used to learn
which devices used to exist. Do not copy old 21.02 DTS, image rules, or platform
scripts into this build blindly.

Missing devices must be adapted to the 23.05 tree style and then validated.

## Sources

- 23.05 source: `padavanonly/immortalwrt-mt798x-6.6`, branch `openwrt-23.05`
- 21.02 name reference: `hanwckf/immortalwrt-mt798x`, branch `openwrt-21.02`
- Local build wrapper: `/home/miunah/my_project/mt798x_build`

## Summary

| Source | Device definitions | Defconfig-covered devices |
|---|---:|---:|
| 21.02 name reference | 91 | 47 |
| 23.05 upstream before this wrapper | 76 | 25 |
| 23.05 wrapper after `scripts/enable_2305_existing_devices.sh` | 76 | 38 |
| 23.05 wrapper after `patches/2305/` adaptations | 91 | 53 |

Important: `imou_lc-hx3001` already exists in 23.05 and is selected by
`defconfig/mt7981-ax3000.config`.

## 23.05 Defconfig-Covered Devices

These devices are selected by this wrapper after running
`scripts/apply_2305_adapted_devices.sh` and
`scripts/enable_2305_existing_devices.sh`. The devices listed in
"23.05 Adapted In This Wrapper" are added by local 23.05-style patches.

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

## 23.05 Present But Not Enabled

These exist in the 23.05 source but are not selected by this wrapper because
they are reference boards, low-level storage variants, shared templates, or
otherwise not useful as normal end-user firmware outputs.

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

## 21.02 Name Reference Missing From 23.05

## 23.05 Adapted In This Wrapper

These devices are implemented as 23.05-style patches under `patches/2305/` and
selected by the wrapper after the patches apply.

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

Notes:

- `cmcc_xr30` and `cmcc_xr30-emmc` are adapted as RAX3000M-family devices
  using the 23.05 DSA switch layout, not the older 21.02 swconfig `gsw`
  description.
- `cmcc_xr30-emmc` has its own MAC offset handling and does not alter the
  existing `cmcc_rax3000m-emmc` offsets.
- The eMMC calibration preinit matcher is corrected from the stale
  `cmcc,rax3000m-em` string to `cmcc,rax3000m-emmc` while adding XR30 eMMC.
- `ikuai_q3000` is adapted from a DSA-style 21.02 board description with
  23.05-compatible SPI bus-width properties and current base-files placement.
- `honor_fur-602`, `newland_nl-wr8103`, `newland_nl-wr9103`, and
  `routerich_ax3000` are adapted from 21.02 MT7981 `gsw` device descriptions.
  This is acceptable for the current 23.05 source because its mt7981 kernel
  config still enables the legacy `MT753X_GSW` driver.
- `routerich_ax3000` writes the 5 GHz Wi-Fi MAC into the current 23.05
  `mt7981.dbdc.b1.dat` path instead of relying on the older `l1dat if2dat`
  helper path.
- `ruijie_rg-x30e*` is adapted as six DSA layouts: normal, stock, and
  firmware2 for both RG-X30E and RG-X30E Pro. The Wi-Fi MAC handling writes the
  current 23.05 MT7981 dat files directly instead of depending on the older
  `l1dat if2dat` helper path.
- `ruijie-rg-x60-pro-stock` reuses the 23.05 `mt7986a-ruijie-rg-x60-pro.dtsi`
  hardware description and the existing `ruijie,rg-x60-pro*` network, MAC, and
  sysupgrade base-files handling.
- The stock profile has its own compatible string,
  `ruijie,rg-x60-pro-stock`, instead of inheriting the old 21.02 compatible
  typo.
- `zyxel_ex5700` is adapted from the 21.02 5.4-compatible EX5700 DTS, not the
  newer mainline `ex5700-telenor` DTS, because this build still targets the
  23.05 5.4 kernel tree.
- This is build-structure adapted. Real-device boot, Ethernet, Wi-Fi, LuCI, and
  sysupgrade still need validation before it should be considered fully proven.

## 21.02 Name Reference Still Missing From 23.05

These are the devices that make 21.02 look broader. They are not implemented in
the checked 23.05 tree and need real 23.05-style adaptation before they can be
added to the build.

```text
xiaomi_mi-router-ax3000t-an8855
xiaomi_mi-router-ax3000t-an8855-stock
```

`xiaomi_mi-router-ax3000t-an8855*` is intentionally not enabled yet. The 21.02
tree includes an `airoha/an8855` switch driver and a shared Xiaomi DTSI node for
this hardware, while the checked 23.05 tree has no AN8855 driver or
`gsw_an8855` node. Adding only two DTS/profile files would likely produce
misleading firmware with broken Ethernet, so this needs a separate AN8855
driver-porting task.

## Adaptation Rules

For every missing device, implement against 23.05:

- DTS/DTSI in the current 23.05 kernel tree style
- `target/linux/mediatek/image/mt7981.mk` or `mt7986.mk` image recipe
- DSA network layout, LED defaults, MAC derivation, Wi-Fi calibration, and
  sysupgrade handling in the current 23.05 base-files style
- Device packages and storage layout matching the real hardware
- Defconfig selection only after the 23.05 recipe is present
- Build test first, then real-device boot, Ethernet, Wi-Fi, LuCI, reset, LED,
  MAC address, and sysupgrade tests

The dedicated maintenance repository should keep those 23.05-style adaptation
patches. This self-use firmware repository should consume the finished support
and build the SCUT package set.
