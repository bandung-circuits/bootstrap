#!/usr/bin/env bash
# detect.sh — OS / arch / region detection. Sourced by install.sh.
# Exports: DETECT_OS, DETECT_ARCH, DETECT_REGION, DETECT_PKG_MANAGER

detect_os() {
  case "$(uname -s)" in
    Darwin) DETECT_OS=macos ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        DETECT_OS=wsl
      else
        DETECT_OS=linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) DETECT_OS=windows ;;
      *) DETECT_OS=unknown ;;
  esac
  export DETECT_OS
}

detect_arch() {
  local a
  a="$(uname -m)"
  case "$a" in
    arm64|aarch64) DETECT_ARCH=arm64 ;;
    x86_64|amd64)  DETECT_ARCH=x86_64 ;;
    *) DETECT_ARCH="$a" ;;
  esac
  export DETECT_ARCH
}

# Region: china -> bailian; otherwise -> deepseek official.
# Heuristic: timezone (UTC+8 China) or locale (zh_CN) or geoip.
# User can override with --provider, so this is only a default hint.
detect_region() {
  DETECT_REGION=international
  # timezone: Asia/Shanghai / Asia/Urumqi / etc -> China
  if [ -n "${TZ:-}" ] && printf '%s' "$TZ" | grep -qiE 'Asia/(Shanghai|Urumqi|Chongqing|Harbin)'; then
    DETECT_REGION=china
  fi
  # /etc/localtime symlink target
  if readlink /etc/localtime 2>/dev/null | grep -qi 'Asia/Shanghai'; then
    DETECT_REGION=china
  fi
  # locale
  if [ -n "${LANG:-}${LC_ALL:-}" ] && printf '%s' "${LANG:-}${LC_ALL:-}" | grep -qiE 'zh_CN|zh_SG'; then
    DETECT_REGION=china
  fi
  export DETECT_REGION
}

detect_pkg_manager() {
  DETECT_PKG_MANAGER=
  if [ "$DETECT_OS" = "macos" ]; then
    if command -v brew >/dev/null 2>&1; then DETECT_PKG_MANAGER=brew; fi
  elif [ "$DETECT_OS" = "linux" ] || [ "$DETECT_OS" = "wsl" ]; then
    if   command -v apt-get >/dev/null 2>&1; then DETECT_PKG_MANAGER=apt
    elif command -v dnf     >/dev/null 2>&1; then DETECT_PKG_MANAGER=dnf
    elif command -v yum     >/dev/null 2>&1; then DETECT_PKG_MANAGER=yum
    elif command -v pacman  >/dev/null 2>&1; then DETECT_PKG_MANAGER=pacman
    fi
  fi
  export DETECT_PKG_MANAGER
}

detect_all() {
  detect_os
  detect_arch
  detect_region
  detect_pkg_manager
}

# Print detected environment for transparency.
detect_print() {
  printf '  OS:        %s\n' "$DETECT_OS"
  printf '  Arch:      %s\n' "$DETECT_ARCH"
  printf '  Region:    %s\n' "$DETECT_REGION"
  printf '  Pkg mgr:   %s\n' "${DETECT_PKG_MANAGER:-none}"
}
