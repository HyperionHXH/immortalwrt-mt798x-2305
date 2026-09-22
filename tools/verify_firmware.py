#!/usr/bin/env python3
"""刷机前在本地验证 ImmortalWrt 固件包（不需要路由器）。

用法：
    python verify_firmware.py <设备名> <.7z 或已解开的目录> [更多...]
    python verify_firmware.py honor_fur-602 xxx.7z --expect chinadns-ng=2026.09.13

做四件事（全部离线）：
  1. 解开 7z，认出每个镜像的类型（UBI / squashfs / tar / FIT …）
  2. sysupgrade 是 tar：读 sysupgrade-<profile>/CONTROL，确认镜像认你手上的机器
     —— 这是"刷错机型/刷错布局"的唯一离线防线
  3. 解开 rootfs 的 squashfs，读 /usr/lib/opkg 的包数据库，得到镜像里真正装了
     哪些包、什么版本（用来核对 passwall 全家桶、Wi-Fi 栈、不该出现的包）
  4. 核对项目约定：/sbin/wifi 必须存在、LAN 默认地址 192.168.1.1

依赖 py7zr、PySquashfsImage；注意读取文件内容要用 entry.read_text()，
库里的 SquashFsImage.read_file() 是坏的（会报 'RegularFile' has no attribute 'start'）。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tarfile
import tempfile

try:
    import py7zr
except ImportError:  # pragma: no cover
    py7zr = None
try:
    from PySquashfsImage import SquashFsImage
except ImportError:  # pragma: no cover
    SquashFsImage = None

PASSWALL_INCLUDE_MAP = {
    "Xray": "xray-core",
    "Hysteria": "hysteria",
    "SingBox": "sing-box",
    "Shadowsocks_Rust_Client": "shadowsocks-rust",
    "V2ray_Geodata": "v2ray-geodata",
    "V2ray_Geoview": "geoview",
}
REQUIRED_ALWAYS = [
    "chinadns-ng",
    "luci-app-passwall",
    "xray-core",
    "sing-box",
    "hysteria",
    "geoview",
    "mtwifi-cfg",
    "luci-app-mtwifi-cfg",
    "dropbear",
]
# 这些包在镜像里必须是"任一命中"（同一意图在不同分支/版本下名字不同）
REQUIRED_ANY_OF = {
    "dnsmasq（或 -full）": ("dnsmasq", "dnsmasq-full"),
    "shadowsocks-rust（或拆分包）": (
        "shadowsocks-rust",
        "shadowsocks-rust-sslocal",
        "shadowsocks-rust-ssserver",
    ),
}
FORBIDDEN = [
    "tailscale",
    "luci-app-tailscale",
    "luci-app-tailscale-community",
    "luci-app-mtk",
    "wifi-profile",
]
REQUIRED_PATHS = [
    "/sbin/wifi",
    "/lib/wifi/mtwifi.sh",
    "/etc/hotplug.d/net/10-mtwifi-detect",
]
MAGIC = [
    (b"hsqs", "squashfs (little-endian)"),
    (b"sqsh", "squashfs (big-endian)"),
    (b"UBI#", "UBI 卷（NAND 机型的 factory 刷机格式）"),
    (b"d00dfeed", "FIT/ITB (devicetree image)"),
    (b"\x27\x05\x19\x56", "uImage (U-Boot legacy)"),
]
WATCH_PKGS = ("luci-app-passwall", "xray-core", "sing-box", "hysteria",
              "shadowsocks-rust", "geoview", "chinadns-ng", "mtwifi-cfg")


def human(n: int) -> str:
    return f"{n / 1048576:.1f} MB"


# 同一个意图在不同分支/版本下的等价包名
ALIASES = {
    "shadowsocks-rust": ("shadowsocks-rust-sslocal", "shadowsocks-rust-ssserver"),
    "v2ray-geodata": ("v2ray-geoip", "v2ray-geosite"),
    "dnsmasq": ("dnsmasq-full",),
    "kmod-fs-ntfs": ("kmod-fs-ntfs3",),
}


def satisfied(pkg: str, pkgs: dict[str, str]) -> bool:
    if pkg in pkgs:
        return True
    return any(a in pkgs for a in ALIASES.get(pkg, ()))


def detect_magic(path: str) -> str:
    with open(path, "rb") as fh:
        head = fh.read(300)
    for sig, name in MAGIC:
        if head.startswith(sig):
            return name
    if head[257:262] == b"ustar":
        return "tar（sysupgrade 容器）"
    return "未知"


def parse_env_block(text: str) -> dict[str, str]:
    """CONTROL 用的是 KEY=VALUE。"""
    out: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def parse_opkg_status(text: str) -> dict[str, str]:
    """opkg status 用的是 'Key: value' 块。"""
    pkgs: dict[str, str] = {}
    for block in text.split("\n\n"):
        name = version = None
        for line in block.splitlines():
            if line.startswith("Package: "):
                name = line[9:].strip()
            elif line.startswith("Version: "):
                version = line[9:].strip()
        if name:
            pkgs[name] = version or "?"
    return pkgs


def read_rootfs(path: str) -> tuple[dict[str, str], dict[str, object], str | None]:
    img = SquashFsImage.from_file(path)
    try:
        files: dict[str, object] = {}
        for entry in img.root.riter():
            files["/" + str(entry.path).lstrip("/")] = entry

        pkgs: dict[str, str] = {}
        status = files.get("/usr/lib/opkg/status") or files.get("/var/lib/opkg/status")
        if status is not None:
            pkgs = parse_opkg_status(status.read_text())
        if not pkgs:  # 回退：用 /usr/lib/opkg/info/*.control
            for p, entry in files.items():
                if p.startswith("/usr/lib/opkg/info/") and p.endswith(".control"):
                    info = parse_env_block(entry.read_text().replace(": ", "=", 1))
                    if info.get("Package"):
                        pkgs[info["Package"]] = "?"

        lan_line = None
        cfg = files.get("/bin/config_generate")
        if cfg is not None:
            for line in cfg.read_text().splitlines():
                if "ipaddr" in line and "192.168." in line:
                    lan_line = line.strip()
                    break
        return pkgs, files, lan_line
    finally:
        img.close()


def expected_from_package_conf(workspace: str) -> list[str]:
    for wrapper in ("immortalwrt-mt798x-2305", "immortalwrt-mt798x-2512"):
        conf = os.path.join(workspace, wrapper, "package.conf")
        if not os.path.isfile(conf):
            continue
        wanted: list[str] = []
        with open(conf, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                if "_INCLUDE_" in line:
                    pkg = PASSWALL_INCLUDE_MAP.get(line.rsplit("_", 1)[-1])
                    if pkg:
                        wanted.append(pkg)
                    continue
                wanted.append(line)
        return sorted(set(wanted))
    return []


def verify(device: str, source: str, workspace: str, workdir: str | None,
           expect: dict[str, str]) -> int:
    tmp = None
    if workdir is None:
        tmp = tempfile.mkdtemp(prefix="fwverify-")
        workdir = tmp
    os.makedirs(workdir, exist_ok=True)

    print(f"\n{'=' * 74}\n设备：{device}\n来源：{source}\n解包目录：{workdir}\n{'=' * 74}")

    if not os.path.exists(source):
        print(f"❌ 路径不存在：{source}")
        print("   （注意：Windows 上要传 Windows 风格的路径；'/c/...' 这类 msys 路径"
              "会被当成当前盘根下的相对路径，文件其实在别处）")
        return 2

    if os.path.isfile(source):
        if not source.lower().endswith(".7z") or py7zr is None:
            print("只支持 .7z 或已解开的目录")
            return 2
        with py7zr.SevenZipFile(source, "r") as z:
            names = z.getnames()
            print("包内文件：")
            for n in names:
                print(f"  - {n}")
            z.extractall(workdir)
        targets = [os.path.join(workdir, n) for n in names if not n.endswith("/")]
    else:
        targets = [os.path.join(source, f) for f in sorted(os.listdir(source))]
        print("目录内容：")
        for t in targets:
            print(f"  - {os.path.basename(t)}")

    problems: list[str] = []
    for path in targets:
        name = os.path.basename(path)
        if name.endswith((".manifest", ".txt", ".json")):
            continue
        kind = detect_magic(path)
        print(f"\n── {name}\n   大小 {human(os.path.getsize(path))}   格式 {kind}")

        rootfs = None
        if kind.startswith("tar"):
            try:
                with tarfile.open(path) as tar:
                    members = {m.name: m for m in tar.getmembers()}
                    control = next((n for n in members if n.endswith("CONTROL")), None)
                    if control:
                        info = parse_env_block(tar.extractfile(members[control]).read().decode())
                        print("   CONTROL：")
                        for k, v in sorted(info.items()):
                            print(f"     {k}={v}")
                        ids = " ".join(info.get(k, "") for k in
                                       ("DEVICE", "BOARD", "SUPPORTED_DEVICES")).split()
                        if device in ids:
                            print(f"   ✅ 镜像认这台设备（{device}）")
                        else:
                            msg = f"{name}: CONTROL 未包含 {device}（实际 {sorted(set(ids))}）"
                            print(f"   ❌ {msg}")
                            problems.append(msg)
                    root = next((n for n in members if n.endswith("/root")), None)
                    if root:
                        rootfs = os.path.join(workdir, "_rootfs.img")
                        with open(rootfs, "wb") as out, tar.extractfile(members[root]) as src:
                            shutil.copyfileobj(src, out)
                        print(f"   rootfs 提取完成（{human(os.path.getsize(rootfs))}）")
                    kern = next((n for n in members if n.endswith("/kernel")), None)
                    if kern:
                        with tar.extractfile(members[kern]) as fh:
                            head = fh.read(4)
                        kfmt = ("FIT/ITB" if head.startswith(b"\xd00dfeed") else
                                "uImage" if head.startswith(b"\x27\x05\x19\x56") else repr(head[:4]))
                        print(f"   kernel {human(members[kern].size)}，格式 {kfmt}")
            except tarfile.TarError as exc:
                print(f"   ⚠ tar 解析失败：{exc}")
        elif kind.startswith("squashfs"):
            rootfs = path

        if rootfs and SquashFsImage is not None:
            try:
                pkgs, files, lan = read_rootfs(rootfs)
            except Exception as exc:  # noqa: BLE001
                print(f"   ⚠ rootfs 解析失败：{exc}")
                pkgs, files, lan = {}, {}, None

            if pkgs:
                print(f"   镜像内已安装包：{len(pkgs)} 个")
                expect_conf = expected_from_package_conf(workspace)
                if expect_conf:
                    missing = [p for p in expect_conf if not satisfied(p, pkgs)]
                    if missing:
                        print(f"   ❌ package.conf 里这些没进镜像：{', '.join(missing)}")
                        problems.append(f"{name}: package.conf 缺 {', '.join(missing)}")
                    else:
                        print(f"   ✅ package.conf 的 {len(expect_conf)} 个包全部在镜像里")
                missing_hard = [p for p in REQUIRED_ALWAYS if p not in pkgs]
                for label, alts in REQUIRED_ANY_OF.items():
                    if not any(a in pkgs for a in alts):
                        missing_hard.append(f"{label}（{' / '.join(alts)}）")
                if missing_hard:
                    print(f"   ❌ 关键组件缺失：{', '.join(missing_hard)}")
                    problems.append(f"{name}: 缺 {', '.join(missing_hard)}")
                else:
                    print("   ✅ 关键组件齐全（passwall 全家桶 + Wi-Fi 栈 + DNS）")
                bad = [p for p in FORBIDDEN if p in pkgs]
                if bad:
                    print(f"   ❌ 不该出现的包：{', '.join(bad)}")
                    problems.append(f"{name}: 出现 {', '.join(bad)}")
                else:
                    print("   ✅ 没有 tailscale / luci-app-mtk / wifi-profile")
                print("   关键版本：")
                for key in WATCH_PKGS:
                    print(f"     {key:20s} {pkgs.get(key, '（缺失）')}")
                for pkg, want in expect.items():
                    got = pkgs.get(pkg)
                    ok = got is not None and (
                        got.startswith(want[:-1]) if want.endswith("*") else got == want)
                    if ok:
                        print(f"   ✅ {pkg} 版本符合预期：{got}")
                    else:
                        msg = f"{name}: {pkg} 版本应为 {want}，实际 {got or '缺失'}"
                        print(f"   ❌ {msg}")
                        problems.append(msg)
            for p in REQUIRED_PATHS:
                ok = p in files
                print(f"   {'✅' if ok else '❌'} {p}")
                if not ok:
                    problems.append(f"{name}: 缺 {p}")
            if lan is not None:
                ok = "192.168.1.1" in lan
                print(f"   {'✅' if ok else '❌'} LAN 默认地址：{lan}")
                if not ok:
                    problems.append(f"{name}: LAN 默认地址异常（{lan}）")

    verdict = "全部通过，可以刷" if not problems else f"{len(problems)} 项需要确认"
    print(f"\n{'=' * 74}\n结论：{verdict}")
    for p in problems:
        print(f"  ❌ {p}")
    print("=" * 74)
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0 if not problems else 1


def find_workspace(start: str) -> str:
    """向上找到包含 wrapper 目录的那一层（脚本放在 <workspace>/<wrapper>/tools/ 时也适用）。"""
    cur = os.path.abspath(start)
    for _ in range(6):
        if any(os.path.isfile(os.path.join(cur, w, "package.conf"))
               for w in ("immortalwrt-mt798x-2305", "immortalwrt-mt798x-2512")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return os.path.abspath(start)


def main() -> int:
    ap = argparse.ArgumentParser(description="刷机前本地验证 ImmortalWrt 固件包",
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("device")
    ap.add_argument("sources", nargs="+")
    ap.add_argument("--workspace", default=None,
                    help="含 wrapper 目录的工作区（默认自动向上查找）")
    ap.add_argument("--keep", help="解包目录（默认临时目录，跑完自动删）")
    ap.add_argument("--expect", action="append", default=[],
                    metavar="PKG=VERSION", help="要求某个包必须是指定版本；以 * 结尾表示前缀匹配，可重复")
    args = ap.parse_args()

    workspace = find_workspace(args.workspace or os.path.dirname(os.path.abspath(__file__)))
    if workspace != args.workspace:
        print(f"（用于核对 package.conf 的工作区：{workspace}）")

    expect = {}
    for item in args.expect:
        if "=" in item:
            k, v = item.split("=", 1)
            expect[k.strip()] = v.strip()

    rc = 0
    for src in args.sources:
        rc |= verify(args.device, os.path.abspath(src), workspace, args.keep, expect)
    return rc


if __name__ == "__main__":
    sys.exit(main())
