#!/bin/bash
set -e -o pipefail

# Read package.conf and append CONFIG_PACKAGE_*=y to .config
while IFS= read -r pkg || [ -n "$pkg" ]; do
  # Skip empty lines and comments
  [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
  echo "CONFIG_PACKAGE_${pkg}=y"
done < ../package.conf >> .config
