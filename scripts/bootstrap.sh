#!/usr/bin/env bash
# 一键准备: 生成诗词库 → 下载霞鹜文楷字体 → 生成 Xcode 工程
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/3 生成诗词库"
if [ ! -d .build/venv ]; then
  python3 -m venv .build/venv
fi
.build/venv/bin/pip install --quiet opencc
.build/venv/bin/python scripts/build_database.py "$@"

echo "==> 2/3 下载字体（霞鹜文楷，SIL OFL 1.1）"
FONT=XiChuang/Resources/Fonts/LXGWWenKai-Regular.ttf
if [ ! -f "$FONT" ]; then
  mkdir -p "$(dirname "$FONT")"
  URL=$(curl -fsSL https://api.github.com/repos/lxgw/LxgwWenKai/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*LXGWWenKai-Regular\.ttf"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/' || true)
  if [ -n "${URL:-}" ] && curl -fL --progress-bar -o "$FONT" "$URL"; then
    echo "    已下载 $FONT"
  else
    rm -f "$FONT"
    echo "    字体下载失败，将使用系统宋体。可手动把 LXGWWenKai-Regular.ttf 放到 XiChuang/Resources/Fonts/"
  fi
fi

echo "==> 3/3 生成 Xcode 工程"
if command -v xcodegen >/dev/null; then
  xcodegen generate
  echo "完成，打开 XiChuang.xcodeproj 即可运行。"
else
  echo "未安装 XcodeGen：brew install xcodegen && xcodegen generate"
fi
