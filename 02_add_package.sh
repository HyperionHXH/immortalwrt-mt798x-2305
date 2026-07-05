#!/usr/bin/env bash
set -euo pipefail

shopt -s extglob

# Read package.conf and append selections to .config.
# Plain package names become CONFIG_PACKAGE_<name>=y. Raw CONFIG_* entries are
# passed through so package.conf can also carry options such as LuCI language.
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
