extends GutTest

func test_apply_effect_adds_and_clamps():
    var base := {"umami": 49}
    var r := StatEngine.apply_effect(base, {"stats": {"umami": 10}})
    assert_eq(int(r["umami"]), StatEngine.STAT_MAX, "doit borner à STAT_MAX")

func test_apply_effect_ignores_named_rule():
    var r := StatEngine.apply_effect(Stats.empty(), {"rule": "stop_oven_seconds", "value": 5})
    for k in Stats.KEYS:
        assert_eq(int(r[k]), 0, "une règle nommée ne touche pas les stats du plat")

func test_compute_dish_sums_ingredients_then_actions():
    var tomate := IngredientRes.from_dict({"id": "tomate", "cost": 2, "stats": {"umami": 3, "acide": 4}})
    var boeuf := IngredientRes.from_dict({"id": "boeuf", "cost": 3, "stats": {"umami": 5, "gras": 3}})
    var cuire := ActionRes.from_dict({"id": "cuire", "base_duration_sec": 45, "effect": {"stats": {"umami": 2, "acide": -1}}})
    var dish := StatEngine.compute_dish([tomate, boeuf], [cuire])
    # umami: 3+5+2=10 ; acide: 4-1=3 ; gras: 3
    assert_eq(int(dish["umami"]), 10)
    assert_eq(int(dish["acide"]), 3)
    assert_eq(int(dish["gras"]), 3)

func test_compute_dish_empty():
    var dish := StatEngine.compute_dish([], [])
    for k in Stats.KEYS:
        assert_eq(int(dish[k]), 0)
