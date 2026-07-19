class_name Stats
extends RefCounted

const KEYS: Array = ["umami", "sucre", "acide", "gras", "amer", "texture"]

static func empty() -> Dictionary:
    var d: Dictionary = {}
    for k in KEYS:
        d[k] = 0
    return d

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
    var out: Dictionary = empty()
    for k in KEYS:
        out[k] = int(a.get(k, 0)) + int(b.get(k, 0))
    return out

static func clamp_stats(s: Dictionary, lo: int, hi: int) -> Dictionary:
    var out: Dictionary = empty()
    for k in KEYS:
        out[k] = clampi(int(s.get(k, 0)), lo, hi)
    return out
