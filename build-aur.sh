#!/usr/bin/env bash
set -euo pipefail

UPLOAD_DIR="/opt/upload"
PKG_LIST="/opt/packages/pkgs.txt"
BUILD_ROOT="/build"
PACKAGES_ROOT="/opt/packages"

# 确保目录存在并设置权限
mkdir -p "$UPLOAD_DIR" "$BUILD_ROOT"
# 对挂载点直接 chmod（宿主若允许，权限会被应用）
chmod -R 777 "$UPLOAD_DIR" || true

if [[ ! -f "$PKG_LIST" ]]; then
  echo "ERROR: 未找到 $PKG_LIST"
  exit 1
fi

# 逐行读取包名；去除所有空白字符（含空格、Tab等）
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  pkg="$(echo "$raw_line" | tr -d '[:space:]')"
  [[ -z "$pkg" ]] && continue

  echo "==> 处理包: $pkg"
  pkg_dir="$BUILD_ROOT/$pkg"

  # 克隆 AUR monorepo 的对应分支到独立目录
  if [[ -d "$pkg_dir" ]]; then
    echo "目录已存在，跳过克隆: $pkg_dir"
  else
    git clone --branch "$pkg" --single-branch \
      https://github.com/archlinux/aur.git \
      "$pkg_dir" --depth=1
  fi

  # 目录归属权给 builder
  chown -R builder:builder "$pkg_dir"

  # 使用非 root 用户编译并自动安装依赖
  sudo -u builder bash -lc "cd '$pkg_dir' && makepkg -si --noconfirm --skipinteg"

  # 复制生成的包到 /opt/upload
  shopt -s nullglob
  found_any=false
  for f in "$pkg_dir"/*.pkg.tar.zst; do
    cp -v "$f" "$UPLOAD_DIR"/
    found_any=true
  done
  if [[ "$found_any" = false ]]; then
    echo "警告: 未在 $pkg_dir 找到 *.pkg.tar.zst（可能仅安装未产出包或包名不一致）"
  fi
done < "$PKG_LIST"


declare -A _seen_dirs
# 使用 -print0 读取 null 分隔，防止空格/特殊字符路径问题
while IFS= read -r -d '' pkgb; do
  dir="$(dirname "$pkgb")"
  # 去重：同一目录只编译一次
  if [[ -n "${_seen_dirs[$dir]:-}" ]]; then
    continue
  fi
  _seen_dirs["$dir"]=1

  # 跳过 /opt/packages 根本身（极少见，但以防万一）
  [[ "$dir" == "$PACKAGES_ROOT" ]] && continue

  echo "==> 编译自写包目录: $dir"
  chown -R builder:builder "$dir"
  if ! sudo -u builder bash -lc "cd '$dir' && makepkg -si --noconfirm --skipinteg"; then
    warn "编译失败: $dir"
    continue
  fi

  shopt -s nullglob
  any=false
  for f in "$dir"/*.pkg.tar.zst; do
    cp -v "$f" "$UPLOAD_DIR"/ || true
    any=true
  done
  if [[ "$any" = false ]]; then
    warn "未在 $dir 找到 *.pkg.tar.zst"
  fi
done < <(find "$PACKAGES_ROOT" -type f -name 'PKGBUILD' -print0 2>/dev/null)

# 再次放宽 upload 目录权限
chmod -R 777 "$UPLOAD_DIR" || true

echo "==> 全部完成。生成的包位于: $UPLOAD_DIR"