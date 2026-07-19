extends GutTest

func test_player_state_roundtrip():
    var p := PlayerState.new()
    p.budget_left = 7
    p.ingredients = ["tomate", "boeuf"]
    p.timeline = ["cuire"]
    p.hand = ["c1"]
    p.deck = ["c2", "c3"]
    p.ready = true
    p.exec_index = 1
    p.exec_elapsed = 2.5
    p.exec_delay_left = 0.0
    p.stat_modifiers = {"umami": 2}
    var back := PlayerState.from_dict(p.to_dict())
    assert_eq(back.budget_left, 7)
    assert_eq(back.ingredients, ["tomate", "boeuf"])
    assert_eq(back.timeline, ["cuire"])
    assert_eq(back.hand, ["c1"])
    assert_eq(back.deck, ["c2", "c3"])
    assert_true(back.ready)
    assert_eq(back.exec_index, 1)
    assert_almost_eq(back.exec_elapsed, 2.5, 0.001)
    assert_eq(int(back.stat_modifiers["umami"]), 2)

func test_phase_enum_values():
    assert_eq(GameState.Phase.PLANNING, 0)
    assert_eq(GameState.Phase.FINISHED, 3)

func test_game_state_roundtrip():
    var s := GameState.new()
    s.seed = 42
    s.rng_state = 123
    s.phase = GameState.Phase.EXECUTION
    s.phase_time_left = 12.0
    s.event_timer_left = 240.0
    s.player_order = ["p0", "p1"]
    s.config = {"ingredient_budget": 10}
    s.result = {}
    var p := PlayerState.new()
    p.budget_left = 3
    s.players = {"p0": p, "p1": PlayerState.new()}
    var back := GameState.from_dict(s.to_dict())
    assert_eq(back.seed, 42)
    assert_eq(back.phase, GameState.Phase.EXECUTION)
    assert_almost_eq(back.phase_time_left, 12.0, 0.001)
    assert_eq(back.player_order, ["p0", "p1"])
    assert_eq(back.players.size(), 2)
    assert_eq(back.players["p0"].budget_left, 3)
