#!/usr/bin/env python3
"""Validate platform connectivity in world.lua maps."""
import re
from pathlib import Path

W = 60

def surfaces(line):
    res, i = [], 0
    while i < len(line):
        if line[i] == "=":
            j = i
            while j < len(line) and line[j] == "=":
                j += 1
            res.append((i + 1, j))
            i = j
        else:
            i += 1
    return res

def can_reach(a, b):
    if abs(a[0] - b[0]) > 4:
        return False
    for a1, a2 in a[1]:
        for b1, b2 in b[1]:
            if not (a2 < b1 - 6 or b2 < a1 - 6):
                return True
    return False

def bfs(lines, start_ch, goal_ch):
    data = {i + 1: surfaces(l) for i, l in enumerate(lines) if surfaces(l)}
    start = next(i for i, l in enumerate(lines, 1) if start_ch in l)
    goal = next(i for i, l in enumerate(lines, 1) if goal_ch in l)
    from collections import deque
    vis, q = {start}, deque([start])
    while q:
        c = q.popleft()
        if c == goal:
            return True, start, goal
        for o in data:
            if o in vis:
                continue
            if can_reach((c, data[c]), (o, data[o])):
                vis.add(o)
                q.append(o)
    return False, start, goal

text = Path(__file__).parent.parent / "world.lua"
for idx, m in enumerate(re.finditer(r"map = \[\[(.*?)\]\]", text.read_text(), re.S), 1):
    lines = [l for l in m.group(1).strip().split("\n")]
    ok, pr, er = bfs(lines, "P", "E")
    ok2, _, fr = bfs(lines, "P", "F")
    print(f"Level {idx}: P->E={ok} (P row {pr}, E row {er})  P->F={ok2} (F row {fr})")
