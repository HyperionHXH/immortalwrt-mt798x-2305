#!/usr/bin/env python3
"""审计 GitHub Release 是否可用：列出全部 Release，并对最新 Release 的每个资产做
"可下载 + 格式正确" 抽查。

抽查方式：走镜像取每个资产的**前 1 KB**（Range），确认
  * HTTP 200/206 且真的返回了字节（不是空文件 / 不是 404 / 不是报错页）
  * 开头是 7z 的 magic（`7z\\xbc\\xaf\\x27\\x1c`）
这样 42 个资产几秒钟就能全部过一遍，不用下 3 GB。

用法：GITHUB_TOKEN=... python audit_releases.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "immortalwrt-mt798x-2305", "tools")))
import fetch_release as fr  # noqa: E402

OWNER = "HyperionHXH"
REPOS = [
    ("immortalwrt-mt798x-2305", "23.05 主线（4 个变种）"),
    ("SCUTclient-immortalwrt-mt798x-2512", "25.12 主线"),
    ("fur602-chinadns-test", "fork chinadns-ng 测试固件"),
]
MIRROR = "https://gh-proxy.com"
SEVENZ_MAGIC = b"7z\xbc\xaf\x27\x1c"

# 修复分界线：早于这个日期的 Release 虽然能下载，但内容有已知缺失
# （2305 的 socat/luci-proto-wireguard 从未进过镜像；fur602 的 fork chinadns-ng 被同名包顶掉）
KNOWN_GAPS = {
    "immortalwrt-mt798x-2305": (
        "20260922",
        "缺 socat + luci-proto-wireguard（package.conf 里是死条目，make defconfig 静默丢弃）"),
    "fur602-chinadns-test": (
        "20260922",
        "chinadns-ng 是上游 2025.08.09，不是 fork 版（覆盖包被 openwrt-passwall-packages 顶掉）"),
}


def variant_of(tag: str) -> str:
    """把 tag 里的日期剥掉，得到"变种"分组键。"""
    import re
    return re.sub(r"-?\d{8}$", "", tag)


def tag_date(tag: str) -> str:
    import re
    m = re.search(r"(\d{8})", tag)
    return m.group(1) if m else "00000000"


def probe(url: str) -> tuple[bool, str]:
    """取前 1 KB，判断是否真是可下载的 7z。"""
    req = urllib.request.Request(url, headers={
        "Range": "bytes=0-1023", "User-Agent": "wb-audit"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            head = resp.read(1024)
            code = resp.status
    except urllib.error.HTTPError as exc:
        return False, f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"
    if code not in (200, 206):
        return False, f"HTTP {code}"
    if len(head) == 0:
        return False, "返回 0 字节"
    if not head.startswith(SEVENZ_MAGIC):
        return False, f"开头不是 7z（{head[:8]!r}）"
    return True, f"HTTP {code}，{len(head)} 字节，7z 头正确"


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("ERROR: GITHUB_TOKEN 为空", file=sys.stderr)
        return 2

    grand_bad: list[str] = []
    for repo, label in REPOS:
        print(f"\n{'=' * 78}\n{OWNER}/{repo}  —— {label}\n{'=' * 78}")
        releases = fr.api(f"{fr.API}/repos/{OWNER}/{repo}/releases?per_page=20", token)
        if not releases:
            print("  （没有任何 Release）")
            continue
        print(f"  共 {len(releases)} 个 Release：")
        gap_date, gap_desc = KNOWN_GAPS.get(repo, ("", ""))
        for rel in releases:
            assets = rel.get("assets", [])
            total = sum(a["size"] for a in assets)
            flag = ""
            if gap_date and tag_date(rel["tag_name"]) < gap_date:
                flag = "  ⚠ 内容过时：" + gap_desc
            print(f"    {rel['tag_name']:52s} {rel['created_at'][:10]}  "
                  f"{len(assets):3d} 个资产  {total/1048576:8.1f} MB{flag}")

        # 每个"变种"取最新的一版（2512 是按变种分 tag 的），逐资产抽查
        latest_of_variant: dict[str, dict] = {}
        for rel in releases:
            key = variant_of(rel["tag_name"])
            cur = latest_of_variant.get(key)
            if cur is None or tag_date(rel["tag_name"]) > tag_date(cur["tag_name"]):
                latest_of_variant[key] = rel

        targets = sorted(latest_of_variant.values(), key=lambda r: r["tag_name"])
        if len(targets) > 1:
            print(f"\n  ── 该仓库按变种分组，抽查 {len(targets)} 个最新 Release ──")

        bad: list[str] = []
        total_assets = 0
        for newest in targets:
            assets = newest.get("assets", [])
            total_assets += len(assets)
            print(f"\n  ── Release `{newest['tag_name']}`（{len(assets)} 个资产）──")
            for a in assets:
                url = f"{MIRROR}/{a['browser_download_url']}"
                ok, detail = probe(url)
                mark = "✅" if ok else "❌"
                if not ok:
                    bad.append(a["name"])
                print(f"    {mark} {a['name']:64s} {a['size']/1048576:7.1f} MB  {detail}")
        print(f"\n  小结：{total_assets - len(bad)}/{total_assets} 个资产可下载且格式正确"
              + (f"；异常：{bad}" if bad else ""))
        grand_bad += [f"{repo}/{n}" for n in bad]

    print(f"\n{'=' * 78}")
    if grand_bad:
        print(f"结论：有 {len(grand_bad)} 个资产异常：{grand_bad}")
        return 1
    print("结论：三个仓库最新 Release 的所有资产均可下载、且都是合法的 7z。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
