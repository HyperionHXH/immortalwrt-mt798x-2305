# ImmortalWrt MT798x Build (openwrt-23.05)

Verified baseline for the MT798x firmware build.

- Source: `padavanonly/immortalwrt-mt798x-6.6`
- Branch: `openwrt-23.05`
- WSL path: `/home/miunah/my_project/mt798x_build`

## Device Variants

See [SUPPORTED_DEVICES_23_05.md](SUPPORTED_DEVICES_23_05.md) for the 21.02 vs 23.05 MT798x device support audit.

| Variant | Platform | Examples |
|---|---|---|
| `mt7981-ax3000` | mt7981 | RAX3000M, ASR3000, CT3003, JCG Q30, 360 T7, GL-MT3000, AX3000T, Routerich AX3000 |
| `mt7986-ax4200` | mt7986 | BPI-R3 Mini, BPI-R3 Mini 110M |
| `mt7986-ax6000` | mt7986 | GL-MT6000, Netcore N60, JDCloud RE-CP-03, Ruijie RG-X60 Pro, Zyxel EX5700 |
| `mt7986-ax6000-256m` | mt7986 | 256 MB RAM variants |

This wrapper currently enables 53 end-user device profiles: 38 that already
exist in the 23.05 source tree, plus `cmcc_xr30`, `cmcc_xr30-emmc`,
`honor_fur-602`, `ikuai_q3000`, `newland_nl-wr8103`,
`newland_nl-wr9103`, `routerich_ax3000`, six `ruijie_rg-x30e*` layouts,
`ruijie-rg-x60-pro-stock`, and `zyxel_ex5700` adapted in `patches/2305/`.
The 21.02 tree is used only as a device-name and 5.4-era hardware reference;
23.05 remains the implementation baseline.

## Build

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

Full build:

```bash
cd /home/miunah/my_project/mt798x_build
JOBS=2 bash build_all.sh
```

`build_all.sh` runs `01_prepare.sh` first, so feeds are refreshed and linked
before `.config` is generated. `01_prepare.sh` also applies the local 23.05
device adaptations and enables the selected end-user profiles. The adaptation
scripts are idempotent, so rerunning them is safe, but manual builds normally
only need the `01_prepare.sh` call above. The feed refresh is required for LuCI
and `lua-cjson`, which are dependencies of `default-settings`,
`default-settings-chn`, and `mtwifi-cfg`.

GitHub Actions are configured for manual `workflow_dispatch` only. Pushes and
pull requests should not start builds automatically.

## Wi-Fi State

Current checked source state, 2026-07-04:

- Keep `openwrt/package/base-files/files/sbin/wifi`.
- Defconfigs use `kmod-mt_wifi`, `mtwifi-cfg`, `luci-app-mtwifi-cfg`, and `wifi-dats`.
- Defconfigs do not use `wifi-profile` or `luci-app-mtk`.
- `mtwifi-cfg` provides `/etc/hotplug.d/net/10-mtwifi-detect`, `/lib/wifi/mtwifi.sh`, and `/lib/netifd/wireless/mtwifi.sh`.

Do not delete `/sbin/wifi`. Older CI notes that removed it belong to a different `luci-app-mtk + wifi-profile` approach and are wrong for this verified 23.05 route.

## Known Working Packages

The user has reported the 23.05 firmware as usable with the expected package set, including scutclient, Passwall, OpenClash, Tailscale, Argon theme, USB storage, and block-mount.

## WSL Note

Use the WSL filesystem for builds. Avoid building under `/mnt/c`.

```bash
sudo tee -a /etc/wsl.conf <<'EOF'
[interop]
appendWindowsPath=false
EOF
```
