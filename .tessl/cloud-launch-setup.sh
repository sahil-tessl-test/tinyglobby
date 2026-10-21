#!/usr/bin/env bash
set -eo pipefail

tool_prefix="$HOME/.local"
mkdir -p "$tool_prefix/bin"
export PATH="$tool_prefix/bin:$PATH"

echo 'Checking Node.js (26 or newer, as used for development in CI)'
node_major=0
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
fi

if [ "$node_major" -lt 26 ]; then
  case "$(uname -s)" in
    Linux) node_os=linux ;;
    Darwin) node_os=darwin ;;
    *) echo 'Cannot install Node.js on this operating system' >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64) node_arch=x64 ;;
    arm64|aarch64) node_arch=arm64 ;;
    *) echo 'Cannot install Node.js on this architecture' >&2; exit 1 ;;
  esac

  echo 'Installing a Node.js 26 release in ~/.local'
  download_dir="$(mktemp -d)"
  trap 'rm -rf "$download_dir"' EXIT
  curl --fail --silent --show-error --location \
    https://nodejs.org/dist/latest-v26.x/SHASUMS256.txt \
    --output "$download_dir/SHASUMS256.txt"
  archive="$(awk -v suffix="-$node_os-$node_arch.tar.gz" \
    'length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix { print $2 }' \
    "$download_dir/SHASUMS256.txt")"
  if [ -z "$archive" ] || [[ "$archive" == *$'\n'* ]]; then
    echo 'Could not identify one compatible Node.js 26 archive' >&2
    exit 1
  fi
  curl --fail --silent --show-error --location \
    "https://nodejs.org/dist/latest-v26.x/$archive" --output "$download_dir/$archive"
  (
    cd "$download_dir"
    awk -v name="$archive" '$2 == name' SHASUMS256.txt > selected-checksum.txt
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum --check selected-checksum.txt
    else
      shasum -a 256 --check selected-checksum.txt
    fi
    tar -xzf "$archive"
  )
  node_dir="$tool_prefix/share/${archive%.tar.gz}"
  mkdir -p "$tool_prefix/share"
  mv "$download_dir/${archive%.tar.gz}" "$node_dir"
  for executable in node npm npx; do
    ln -sfn "$node_dir/bin/$executable" "$tool_prefix/bin/$executable"
  done
fi

echo "Using Node.js $(node --version)"
pnpm_version="$(node -p 'require("./package.json").devEngines.packageManager.version')"
echo "Checking pnpm $pnpm_version from package.json"
if ! command -v pnpm >/dev/null 2>&1 || [ "$(pnpm --version)" != "$pnpm_version" ]; then
  echo "Installing pnpm $pnpm_version in ~/.local"
  (
    cd "$tool_prefix"
    npm install --global --prefix "$tool_prefix" "pnpm@$pnpm_version"
  )
fi

if [ "$(pnpm --version)" != "$pnpm_version" ]; then
  echo "Expected pnpm $pnpm_version; found $(pnpm --version)" >&2
  exit 1
fi

echo 'Installing dependencies from pnpm-lock.yaml'
pnpm install --frozen-lockfile
