#!/usr/bin/env python3
"""从 GitHub Release 稳健地取固件资产（断点续传 + 大小校验）。

这个环境的网络到 GitHub 大文件下载经常被中途掐断（curl --retry 也救不回来），
所以这里做两件 curl 不擅长的事：
  * 断点续传：用 HTTP Range 从已有字节处继续，断多少次都能接着下；
  * 大小校验：下载完比对 assets API 报的 size，不一致就继续续传，直到对上。

用法：
    python fetch_release.py --repo HyperionHXH/immortalwrt-mt798x-2305 --latest \
        --match honor_fur-602 --match cmcc_rax3000m --out .tmp-verify/dl
    python fetch_release.py --repo owner/name --tag <tag> --match .7z --out dir --list

令牌从环境变量 GITHUB_TOKEN 取（不打印、不落盘）。
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
CHUNK = 1 << 20  # 1 MiB


def api(url: str, token: str, tries: int = 6) -> dict:
    """带重试的 API 调用 —— 这台机器到 GitHub 的连接会整段抽风（10054/10060/
    RemoteDisconnected），一次失败不该让上层脚本崩掉。"""
    last: Exception | None = None
    for attempt in range(1, tries + 1):
        req = urllib.request.Request(url, headers={
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "wb-fetch-release",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise RuntimeError(
                    "HTTP 401：令牌无效或为空（检查 GITHUB_TOKEN 是否取到；"
                    "空字符串会被发成 'Authorization: token '，GitHub 报 401）") from exc
            last = exc
            if attempt < tries:
                time.sleep(min(3 * attempt, 20))
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as exc:
            last = exc
            if attempt < tries:
                time.sleep(min(3 * attempt, 20))
    raise RuntimeError(f"API 连续 {tries} 次失败：{url} :: {last}")


def resolve_tag(repo: str, token: str, tag: str | None) -> str:
    if tag:
        return tag
    releases = api(f"{API}/repos/{repo}/releases?per_page=20", token)
    if not releases:
        raise SystemExit(f"{repo} 还没有任何 Release")
    for rel in releases:
        if any(a["name"].endswith(".7z") for a in rel.get("assets", [])):
            return rel["tag_name"]
    return releases[0]["tag_name"]


def assets_of(repo: str, tag: str, token: str) -> list[dict]:
    rel = api(f"{API}/repos/{repo}/releases/tags/{tag}", token)
    return rel.get("assets", [])


def download(url: str, dest: str, size: int, token: str, tries: int = 40) -> bool:
    """40 次尝试、退避到 30 秒 —— 实测这台机器会出现持续十分钟级的整段断网，
    12 次尝试不够用（2026-09-22 就是这么失败的）。"""
    for attempt in range(1, tries + 1):
        have = os.path.getsize(dest) if os.path.exists(dest) else 0
        if have == size:
            return True
        if have > size:  # 上次下坏了，从头来
            os.remove(dest)
            have = 0
        headers = {"User-Agent": "wb-fetch-release"}
        if token:
            headers["Authorization"] = f"token {token}"
        if have:
            headers["Range"] = f"bytes={have}-"
        req = urllib.request.Request(url, headers=headers)
        mode = "ab" if have else "wb"
        try:
            with urllib.request.urlopen(req, timeout=120) as resp, open(dest, mode) as out:
                got = have
                while True:
                    chunk = resp.read(CHUNK)
                    if not chunk:
                        break
                    out.write(chunk)
                    got += len(chunk)
                    pct = got * 100 // size if size else 0
                    print(f"\r     {os.path.basename(dest)}: {got/1048576:.1f}/{size/1048576:.1f} MB ({pct}%)",
                          end="", flush=True)
            print()
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as exc:
            print(f"\n     第 {attempt}/{tries} 次中断（{exc}），{min(3 * attempt, 30)}s 后续传…")
            time.sleep(min(3 * attempt, 30))
            continue
        if os.path.exists(dest) and os.path.getsize(dest) == size:
            return True
    return os.path.exists(dest) and os.path.getsize(dest) == size


def main() -> int:
    ap = argparse.ArgumentParser(description="稳健下载 GitHub Release 资产")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--tag")
    ap.add_argument("--latest", action="store_true", help="用最新一个带资产的 Release")
    ap.add_argument("--match", action="append", default=[], help="资产名需包含的子串，可重复")
    ap.add_argument("--out", default=".")
    ap.add_argument("--list", action="store_true", help="只列出资产，不下载")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        # 空 token 会发成 "Authorization: token "，GitHub 直接回 401 Bad credentials，
        # 报错信息看起来像权限问题、其实是没取到令牌（2026-09-22 踩过）。
        print("错误：GITHUB_TOKEN 为空。取法：\n"
              "    printf 'protocol=https\\nhost=github.com\\n\\n' | git-credential-manager get",
              file=sys.stderr)
        return 2
    tag = resolve_tag(args.repo, token, None if args.latest or not args.tag else args.tag)
    assets = assets_of(args.repo, tag, token)
    picked = [a for a in assets if not args.match or any(m in a["name"] for m in args.match)]

    print(f"{args.repo}  release={tag}  资产 {len(assets)} 个，命中 {len(picked)} 个")
    for a in picked:
        print(f"  {a['name']}  {a['size'] / 1048576:.1f} MB")
    if args.list or not picked:
        return 0

    os.makedirs(args.out, exist_ok=True)
    failed: list[str] = []
    for a in picked:
        dest = os.path.join(args.out, a["name"])
        if os.path.exists(dest) and os.path.getsize(dest) == a["size"]:
            print(f"  跳过（已完整）：{a['name']}")
            continue
        print(f"  下载 {a['name']} …")
        ok = download(a["browser_download_url"], dest, a["size"], token)
        print(f"    {'完成' if ok else '失败'}：{a['name']} ")
        if not ok:
            failed.append(a["name"])

    if failed:
        print(f"\n以下资产仍不完整（可重跑本脚本续传）：")
        for f in failed:
            print(f"  - {f}")
        return 1
    print("\n全部资产下载完成。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
