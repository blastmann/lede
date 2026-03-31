#!/usr/bin/env bash
#
# scripts/openclash.sh — OpenClash 集成脚本
#
# 用法:
#   scripts/openclash.sh setup              下载源码 + 编译 po2lmo
#   scripts/openclash.sh preload            下载 UI 面板 + clash meta 核心
#   scripts/openclash.sh setup preload      两步一起执行
#
# 需要在 OpenWrt 源码根目录执行，preload 前需要先 make defconfig 生成 .config
#

set -euo pipefail

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$TOPDIR/package/luci-app-openclash"

# ── setup: 下载 OpenClash 源码并编译 po2lmo ────────────────────────────

do_setup() {
  echo "==> Setting up OpenClash source..."

  rm -rf "$PKG_DIR"
  mkdir -p "$PKG_DIR"
  pushd "$PKG_DIR" >/dev/null

  git init -q
  git remote add -f origin https://github.com/vernesong/OpenClash.git
  git config core.sparsecheckout true
  echo "luci-app-openclash" >> .git/info/sparse-checkout
  git pull --depth 1 origin master
  git branch --set-upstream-to=origin/master master

  # sparse checkout 得到 luci-app-openclash/ 子目录，展平到 PKG_DIR
  shopt -s dotglob nullglob
  mv luci-app-openclash/* .
  rmdir luci-app-openclash

  popd >/dev/null

  # 编译并安装 po2lmo
  echo "==> Building po2lmo..."
  pushd "$PKG_DIR/tools/po2lmo" >/dev/null
  make
  sudo make install
  popd >/dev/null

  echo "==> OpenClash setup complete."
}

# ── preload: 下载 UI 面板和 clash meta 核心 ─────────────────────────────

do_preload() {
  echo "==> Preloading OpenClash runtime assets..."

  local pkg_root="$PKG_DIR/root"
  local ui_root="$pkg_root/usr/share/openclash/ui"
  local core_root="$pkg_root/etc/openclash/core"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  mkdir -p "$ui_root/dashboard" "$ui_root/yacd" "$ui_root/zashboard" "$ui_root/metacubexd" "$core_root"

  # ---- 辅助函数: 下载并解压 zip ----
  download_and_unpack_zip() {
    local url="$1"
    local include_dir="$2"
    local target_dir="$3"
    local zip_path="$tmp_dir/$(basename "$target_dir").zip"
    local unpack_dir="$tmp_dir/$(basename "$target_dir")"

    rm -rf "$zip_path" "$unpack_dir"
    echo "    Downloading $(basename "$target_dir")..."
    curl -fL --retry 3 --connect-timeout 30 "$url" -o "$zip_path"
    unzip -q "$zip_path" -d "$unpack_dir"
    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    cp -a "$unpack_dir/$include_dir"/. "$target_dir/"
  }

  # ---- 下载 4 个 UI 面板 ----
  download_and_unpack_zip \
    "https://codeload.github.com/ayanamist/clash-dashboard/zip/refs/heads/gh-pages" \
    "clash-dashboard-gh-pages" "$ui_root/dashboard"

  download_and_unpack_zip \
    "https://codeload.github.com/MetaCubeX/Yacd-meta/zip/refs/heads/gh-pages" \
    "Yacd-meta-gh-pages" "$ui_root/yacd"

  download_and_unpack_zip \
    "https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip" \
    "dist" "$ui_root/zashboard"

  download_and_unpack_zip \
    "https://codeload.github.com/MetaCubeX/metacubexd/zip/refs/heads/gh-pages" \
    "metacubexd-gh-pages" "$ui_root/metacubexd"

  # ---- 根据目标架构下载 clash meta 核心 ----
  local config_file="$TOPDIR/.config"
  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: $config_file not found. Run 'make defconfig' first." >&2
    exit 1
  fi

  local arch_packages
  arch_packages="$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\(.*\)"$/\1/p' "$config_file" | head -n1)"

  if [[ -z "$arch_packages" ]]; then
    echo "ERROR: CONFIG_TARGET_ARCH_PACKAGES is empty in $config_file" >&2
    echo "       Make sure target architecture is set before running 'make defconfig'." >&2
    exit 1
  fi

  local core_arch=""
  case "$arch_packages" in
    aarch64_*)                                          core_arch="linux-arm64" ;;
    arm_cortex-a*|arm_*neon*|arm_*vfpv3*|arm_*vfpv4*)  core_arch="linux-armv7" ;;
    arm_arm1176jzf-s_vfp|arm_*arm11*|arm_*vfp)         core_arch="linux-armv6" ;;
    arm_*)                                              core_arch="linux-armv5" ;;
    i386*|i486*|i586*|i686*)                            core_arch="linux-386" ;;
    mips64_*)                                           core_arch="linux-mips64" ;;
    mipsel_*)                                           core_arch="linux-mipsle-softfloat" ;;
    mips_*)                                             core_arch="linux-mips-softfloat" ;;
    x86_64)                                             core_arch="linux-amd64" ;;
    *)
      echo "ERROR: Unsupported architecture: $arch_packages" >&2
      rm -rf "$tmp_dir"
      exit 1
      ;;
  esac

  echo "    Downloading clash meta core ($core_arch)..."
  curl -fL --retry 3 --connect-timeout 30 \
    "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-${core_arch}.tar.gz" \
    -o "$tmp_dir/clash_meta.tar.gz"
  tar -xzf "$tmp_dir/clash_meta.tar.gz" -C "$tmp_dir"
  install -m 4755 "$tmp_dir/clash" "$core_root/clash_meta"

  rm -rf "$tmp_dir"
  echo "==> Preload complete (arch=$arch_packages, core=$core_arch)."
}

# ── 主入口 ──────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 {setup|preload} [...]" >&2
  exit 1
fi

for cmd in "$@"; do
  case "$cmd" in
    setup)   do_setup   ;;
    preload) do_preload  ;;
    *)
      echo "Unknown command: $cmd" >&2
      echo "Usage: $0 {setup|preload} [...]" >&2
      exit 1
      ;;
  esac
done
