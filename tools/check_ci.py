#!/usr/bin/env python3
"""推送前检查各 wrapper 的 GitHub Actions workflow（不需要联网）。

做三件事：
  1. YAML 语法（pyyaml）
  2. 每个 step 的 run: 脚本做 bash -n 语法检查
  3. 找出所有 `timeout <时长>` 并逐个用本机 GNU timeout 验证时长写法是否合法

第 3 条是重点：`timeout 4h30m` 会被 GNU timeout 判为非法时长、以 125 退出，
make 根本不会执行，而 CI 只会显示"编译失败"。2026-09-22 就是这样让 2305 的
四个 job 全挂、还白跑了一条 45 分钟的单线程重试。

用法：
    python check_ci.py                # 检查工作区里所有 wrapper
    python check_ci.py immortalwrt-mt798x-2305
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("需要 pyyaml：pip install pyyaml", file=sys.stderr)
    sys.exit(2)

WRAPPERS = ("immortalwrt-mt798x-2305", "immortalwrt-mt798x-2512", "fur602-chinadns-test")
DURATION_RE = re.compile(
    r"\btimeout\s+(?:--[a-z-]+(?:=\S+)?\s+)*([0-9][0-9.]*[a-zA-Z][a-zA-Z0-9]*)")
# 注意末尾的 [a-zA-Z0-9]*：少了它，"4h30m" 只会匹配到合法的前缀 "4h"，
# 非法时长就被漏掉了（第一版就是这么漏的）。


def bash_path() -> str:
    from shutil import which
    return which("bash") or "bash"


def check_duration(dur: str) -> bool | None:
    """用 timeout 验证时长写法（0=合法，125=非法，None=本机没有 GNU timeout）。

    必须经由 bash 调用：在 Windows 上直接 subprocess 调 "timeout" 会落到
    C:\\Windows\\System32\\timeout.exe（那是另一个完全不同的程序）。
    """
    res = subprocess.run([bash_path(), "-c", 'command -v timeout >/dev/null || exit 127; '
                                             'timeout "$1" true', "check", dur],
                         capture_output=True)
    if res.returncode == 127:
        return None
    return res.returncode == 0


def iter_steps(doc: dict):
    for job_name, job in (doc.get("jobs") or {}).items():
        for step in job.get("steps") or []:
            run = step.get("run")
            if isinstance(run, str):
                yield job_name, step.get("name", "(未命名)"), run


def check_wrapper(path: str) -> int:
    wf = os.path.join(path, ".github", "workflows")
    if not os.path.isdir(wf):
        print(f"  {path}: 没有 .github/workflows，跳过")
        return 0
    problems = 0
    for fn in sorted(os.listdir(wf)):
        if not fn.endswith((".yml", ".yaml")):
            continue
        full = os.path.join(wf, fn)
        try:
            with open(full, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except Exception as exc:  # noqa: BLE001
            print(f"  ❌ {fn}: YAML 解析失败：{exc}")
            problems += 1
            continue

        for job, step, run in iter_steps(doc or {}):
            # bash -n：用 stdin 避免临时文件名带来的转义问题
            res = subprocess.run([bash_path(), "-n", "-s"], input=run.encode(),
                                 capture_output=True)
            if res.returncode != 0:
                print(f"  ❌ {fn} :: {job} :: {step} —— shell 语法错误")
                print(f"     {res.stderr.decode(errors='replace').strip()[:400]}")
                problems += 1

            for dur in sorted(set(DURATION_RE.findall(run))):
                verdict = check_duration(dur)
                if verdict is False:
                    print(f"  ❌ {fn} :: {job} :: {step} —— 非法 timeout 时长 '{dur}'"
                          f"（GNU timeout 只接受单个单位，如 270m / 4h / 45m）")
                    problems += 1
                elif verdict is None:
                    print(f"  ⚠ {fn} :: {job} :: {step} —— 本机没有 GNU timeout，跳过 '{dur}' 的校验")

        n_steps = sum(1 for _ in iter_steps(doc or {}))
        n_dur = len({d for _, _, r in iter_steps(doc or {}) for d in DURATION_RE.findall(r)})
        if problems == 0:
            print(f"  ✅ {fn}：{n_steps} 个 step，{n_dur} 个 timeout 时长全部合法")
    return problems


def locate(name: str, start: str) -> str | None:
    """在 start 及其上 4 层里找到 wrapper 目录（脚本可放在 <workspace>/<wrapper>/tools/）。"""
    cur = os.path.abspath(start)
    for _ in range(5):
        cand = os.path.join(cur, name)
        if os.path.isdir(cand):
            return cand
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return None


def main() -> int:
    targets = sys.argv[1:] or list(WRAPPERS)
    start = os.getcwd()
    here = os.path.dirname(os.path.abspath(__file__))
    total = 0
    for t in targets:
        p = locate(t, start) or locate(t, here)
        if p is None:
            print(f"{t}: 找不到该目录，跳过")
            continue
        print(f"{os.path.basename(p.rstrip('/'))}:")
        total += check_wrapper(p)
    print("\n结论：" + ("全部通过" if total == 0 else f"{total} 处问题需要修"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
