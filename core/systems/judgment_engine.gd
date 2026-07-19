class_name JudgmentEngine
extends RefCounted

static func score_dish(dish_stats: Dictionary, criteria: Array) -> float:
    var total := 0.0
    for c in criteria:
        total += float(dish_stats.get(c.id, 0)) * c.weight
    return total

static func judge(dish_a: Dictionary, dish_b: Dictionary, criteria: Array) -> Dictionary:
    var sa := score_dish(dish_a, criteria)
    var sb := score_dish(dish_b, criteria)
    var winner := "draw"
    if sa > sb:
        winner = "a"
    elif sb > sa:
        winner = "b"
    return {"score_a": sa, "score_b": sb, "winner": winner}
