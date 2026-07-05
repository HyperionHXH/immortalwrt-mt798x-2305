#!/usr/bin/env bash
set -euo pipefail

shopt -s extglob

# 读取 package.conf 并把选择追加到 .config。
# 普通包名会变成 CONFIG_PACKAGE_<name>=y；原始 CONFIG_* 行会原样写入，
# 这样 package.conf 也能携带 LuCI 语言之类的选项。
while IFS= read -r entry || [ -n "$entry" ]; do
  entry="${entry//$'\r'/}"
  entry="${entry##+([[:space:]])}"
  entry="${entry%%+([[:space:]])}"

  [[ -z "$entry" || "$entry" == \#* ]] && continue

  if [[ "$entry" == CONFIG_* ]]; then
    echo "$entry"
  else
    echo "CONFIG_PACKAGE_${entry}=y"
  fi
done < ../package.conf >> .config
