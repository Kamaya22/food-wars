extends GutTest

func test_stats_effect_accumulates():
    var p := PlayerState.new()
    p.stat_modifiers = Stats.empty()
    assert_eq(EffectResolver.apply(p, {"stats": {"umami": 2}}), "stats")
    EffectResolver.apply(p, {"stats": {"umami": 3, "acide": 1}})
    assert_eq(int(p.stat_modifiers["umami"]), 5)
    assert_eq(int(p.stat_modifiers["acide"]), 1)

func test_delay_rule():
    var p := PlayerState.new()
    assert_eq(EffectResolver.apply(p, {"rule": "delay_execution_seconds", "value": 5}), "delay")
    assert_almost_eq(p.exec_delay_left, 5.0, 0.001)

func test_unknown_rule_is_noop():
    var p := PlayerState.new()
    p.stat_modifiers = Stats.empty()
    assert_eq(EffectResolver.apply(p, {"rule": "invoquer_dragon"}), "noop")
    assert_almost_eq(p.exec_delay_left, 0.0, 0.001)

func test_empty_effect_is_noop():
    var p := PlayerState.new()
    assert_eq(EffectResolver.apply(p, {}), "noop")
