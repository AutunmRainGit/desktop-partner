#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量切割像素动画精灵表

复用 /Users/atr/Desktop/图片预处理脚本/app_001.py 的 compute_bounds 均分逻辑：
    - 每帧 256x256，列数 = 宽 // 256，行数 = 高 // 256
    - 从左到右、从上到下，三位数编号 001.png、002.png……
    - 跳过完全空白的格子（全透明或全白），与 blink/death 等已有目录一致
    - 原精灵表文件保留不动，帧图直接生成在原目录中
"""

import os
import re
import sys

from PIL import Image

SCRIPT_DIR = "/Users/atr/Desktop/图片预处理脚本"
sys.path.insert(0, SCRIPT_DIR)
from app_001 import compute_bounds  # noqa: E402

ANIM_ROOT = "/Users/atr/Desktop/像素动画"
FOLDERS = [
    "happy", "hungry", "idle", "idle-sleep", "level_up", "sleepy",
    "start-sleep", "stop-sleep", "walk_left", "walk_right", "wave", "weak",
]
FRAME_SIZE = 256
FRAME_NAME_RE = re.compile(r"^\d+\.png$")      # 已切出的帧，不再处理
SHEET_ORDER_RE = re.compile(r"(\d{10,})")       # 文件名里的长数字串（时间戳）用于排序


def is_blank(piece):
    """格子完全透明，或不透明但接近全白，视为空白帧。"""
    alpha = piece.getchannel("A")
    if alpha.getbbox() is None:
        return True
    extrema = piece.convert("RGB").getextrema()
    return all(lo >= 250 for (lo, _hi) in extrema)


def sheet_sort_key(path):
    m = SHEET_ORDER_RE.search(os.path.basename(path))
    return (int(m.group(1)) if m else 0, os.path.basename(path))


def process_folder(folder):
    folder_path = os.path.join(ANIM_ROOT, folder)
    sheets = [
        os.path.join(folder_path, f)
        for f in os.listdir(folder_path)
        if f.lower().endswith(".png") and not FRAME_NAME_RE.match(f)
    ]
    sheets.sort(key=sheet_sort_key)
    if not sheets:
        print("[{}] 没有找到精灵表，跳过".format(folder))
        return

    idx = 1
    for sheet_path in sheets:
        image = Image.open(sheet_path).convert("RGBA")
        width, height = image.size
        if width % FRAME_SIZE or height % FRAME_SIZE:
            print("[{}] {} 尺寸 {}x{} 不是 {} 的整数倍，跳过".format(
                folder, os.path.basename(sheet_path), width, height, FRAME_SIZE))
            continue
        cols = width // FRAME_SIZE
        rows = height // FRAME_SIZE
        col_bounds = compute_bounds(width, cols)
        row_bounds = compute_bounds(height, rows)

        kept, skipped = 0, 0
        for (y0, y1) in row_bounds:
            for (x0, x1) in col_bounds:
                piece = image.crop((x0, y0, x1, y1))
                if is_blank(piece):
                    skipped += 1
                    continue
                name = "{:03d}.png".format(idx)
                piece.save(os.path.join(folder_path, name), "PNG")
                idx += 1
                kept += 1
        print("[{}] {} -> {}x{} 网格，保留 {} 帧，跳过空白 {} 格{}".format(
            folder, os.path.basename(sheet_path), cols, rows, kept, skipped,
            "（背景不透明）" if image.getchannel("A").getextrema()[0] == 255 else ""))


def main():
    # 可传目录名参数只处理部分目录，例如：python3 split_pixel_animations.py eat_leaf
    targets = sys.argv[1:] or FOLDERS
    for folder in targets:
        process_folder(folder)
    print("完成，原文件均未改动。")


if __name__ == "__main__":
    main()
