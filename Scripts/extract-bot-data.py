#!/usr/bin/env python3
"""Regenerate Sources/Pulse/Resources/bot-data.json.

    python3 Scripts/extract-bot-data.py \\
        <checkout>/component/original-data.js \\
        Sources/Pulse/Resources/bot-data.json

The checkout is iduu/grokbot-animation. What that data is and why it is
vendored rather than fetched: Docs/decisions/bot-mark-geometry.md.

`original-data.js` is generated, one `export const NAME = <literal>;` per
line, and every literal is already JSON-compatible — so this reads it as text
and never executes it. The catalogue (state order, labels, which state owns
which morph) is transcribed below from catalog.js for the same reason.
"""
import json
import re
import sys

STATES = [
    ("idle", "Idle", "待机", None),
    ("sleeping", "Sleeping", "睡眠", None),
    ("waking", "Waking", "醒来", None),
    ("listening", "Listening", "倾听", None),
    ("thinking", "Thinking", "思考", "dots"),
    ("searching", "Searching", "搜索", None),
    ("working", "Working", "工作", None),
    ("excited", "Excited", "兴奋", None),
    ("surprised", "Surprised", "惊讶", None),
    ("suspicious", "Suspicious", "怀疑", None),
    ("angry", "Angry", "生气", None),
    ("drowsy", "Drowsy", "困倦", None),
    ("happy", "Happy", "开心", None),
    ("curious", "Curious", "好奇", None),
    ("confused", "Confused", "困惑", None),
    ("bored", "Bored", "无聊", None),
    ("proud", "Proud", "得意", None),
    ("shy", "Shy", "害羞", None),
    ("sad", "Sad", "难过", None),
    ("laughing", "Laughing", "大笑", None),
    ("scared", "Scared", "害怕", None),
    ("playful", "Playful", "调皮", None),
    ("celebrate", "Celebrate", "庆祝", None),
    ("orbit", "Orbit", "轨道", "orbit"),
    ("radar", "Radar", "雷达", "radar"),
    ("progress", "Progress", "进度", "progress"),
    ("spawning", "Spawning", "生成", "gather"),
    ("humming", "Humming", "运转", None),
    ("loading", "Loading", "加载", "whirl"),
    ("dictating", "Dictating", "听写", "wave"),
    ("writing", "Writing", "书写", "pencil"),
    ("sending", "Sending", "发送", "send"),
    ("receiving", "Receiving", "接收", "receive"),
    ("uploading", "Uploading", "上传", "dock"),
    ("notifying", "Notifying", "通知", None),
    ("alerting", "Alerting", "警报", "bang"),
    ("dragging", "Dragging", "拖拽", None),
    ("bouncing", "Bouncing", "弹跳", "ball"),
    ("powering-down", "Powering down", "关机", "standby"),
]

SHAPES = [
    ("blob", "Blob", "圆形"), ("pebble", "Pebble", "卵石"), ("bean", "Bean", "豆形"),
    ("egg", "Egg", "蛋形"), ("squircle", "Squircle", "圆角方形"), ("tablet", "Tablet", "圆角矩形"),
    ("capsule", "Capsule", "胶囊"), ("cylinder", "Cylinder", "圆柱"), ("hex", "Hexagon", "六边形"),
    ("gem", "Gem", "宝石"), ("crystal", "Crystal", "水晶"), ("wedge", "Wedge", "三角楔形"),
    ("shield", "Shield", "盾牌"), ("dome", "Dome", "拱顶"), ("arch", "Arch", "拱门"),
    ("cloud", "Cloud", "云朵"), ("teardrop", "Teardrop", "水滴"), ("leaf", "Leaf", "叶片"),
]

ARGUMENT_COUNT = {"M": 2, "L": 2, "C": 6, "Q": 4, "Z": 0}
TOKENS = re.compile(r"[MLCQZmlcqz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?")


def exports(source_path):
    """Every `export const NAME = <json literal>;` line, parsed as JSON."""
    values = {}
    with open(source_path, encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"export const (\w+) = (.*);\s*$", line)
            if match:
                values[match.group(1)] = json.loads(match.group(2))
    return values


def parse_path(path):
    """Pre-parse an SVG path into numeric segments, so Swift replays it
    without a path parser. Upstream uses absolute M, L, C, Q and Z only."""
    tokens = TOKENS.findall(path)
    segments = []
    index = 0
    op = None
    while index < len(tokens):
        token = tokens[index]
        if token.isalpha():
            if token.upper() != token:
                raise ValueError(f"relative command {token!r} is not handled")
            op = token
            index += 1
            if op == "Z":
                segments.append({"op": op, "values": []})
                continue
        if op is None:
            raise ValueError("path did not start with a command")
        count = ARGUMENT_COUNT[op]
        values = [float(value) for value in tokens[index:index + count]]
        if len(values) != count:
            raise ValueError(f"short {op} segment at token {index}")
        segments.append({"op": op, "values": [round(value, 3) for value in values]})
        index += count
        if op == "M":
            op = "L"  # repeated pairs after a moveto are implicit linetos
    return segments


def ring(points):
    return [[round(x, 3), round(y, 3)] for x, y in points]


def main():
    source, out = sys.argv[1], sys.argv[2]
    raw = exports(source)
    state_data = raw["ORIGINAL_STATE_DATA"]

    shapes = {}
    for key, shape in raw["SHAPES"].items():
        shapes[key] = {
            "ring": ring(shape["ring"]),
            "path": parse_path(shape["path"]),
            "face": {name: shape["face"][name] for name in ("x", "y", "sx", "sy", "eye")},
            "tiltScale": shape["tiltScale"],
            "beltRadius": shape["beltRadius"],
            "radius": shape["radius"],
            "top": round(shape["top"], 3),
            "bottom": round(shape["bottom"], 3),
            "sides": shape.get("sides") or 0,
            "solid": [[round(value, 3) for value in sphere] for sphere in shape["solid"]]
                     if shape.get("solid") else None,
            "spanSamples": ring(shape["spanSamples"]) if shape.get("spanSamples") else None,
        }

    output = {
        "headC": raw["HEAD_C"],
        "eyeHalf": raw["EYE_HALF"],
        "circleRing": ring(raw["CIRCLE_RING"]),
        "starPath": parse_path(raw["STAR_PATH"]),
        "starGold": raw["STAR_GOLD"],
        "shapes": shapes,
        "shapeOrder": [identifier for identifier, _, _ in SHAPES],
        "shapeLabels": {identifier: {"en": en, "zh": zh} for identifier, en, zh in SHAPES},
        "expressions": [[ring(eye) for eye in pair] for pair in raw["EXPRESSIONS"]],
        "states": [{
            "id": identifier, "en": en, "zh": zh, "morph": morph,
            "blinkCadence": state_data["BLINK_CADENCE"][identifier],
            "expressionCadence": state_data["EXPRESSION_CADENCE"][identifier],
            "expressionPool": state_data["EXPRESSION_POOLS"][identifier],
        } for identifier, en, zh, morph in STATES],
    }

    with open(out, "w", encoding="utf-8") as handle:
        json.dump(output, handle, separators=(",", ":"), ensure_ascii=False)
    print(f"shapes {len(shapes)}, expressions {len(output['expressions'])}, "
          f"states {len(output['states'])}, "
          f"{len(open(out, 'rb').read()) / 1024:.0f}KB")


if __name__ == "__main__":
    main()
