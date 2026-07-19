extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func _types(events: Array) -> Array:
    return events.map(func(e): return e.type)

func test_dish_compute_uses_applied_actions_only():
    var s := _fresh()
    var p: PlayerState = s.players["p0"]
    p.ingredients = ["boeuf"]          # umami 5, gras 3
    p.timeline = ["cuire", "mixer"]
    p.exec_index = 1                    # seule "cuire" appliquée (umami +2, acide -1)
    p.stat_modifiers = Stats.empty()
    var dish := Dish.compute(_db, p)
    assert_eq(int(dish["umami"]), 7)
    assert_eq(int(dish["acide"]), -1)   # (pas de mixer)

func test_planning_ends_when_both_ready():
    var s := _fresh()
    s.players["p0"].ready = true
    s.players["p1"].ready = true
    var ev := PhaseMachine.maybe_end_planning(_db, s)
    assert_eq(s.phase, GameState.Phase.EXECUTION)
    assert_true(_types(ev).has("phase_changed"))

func test_planning_stays_if_only_one_ready():
    var s := _fresh()
    s.players["p0"].ready = true
    PhaseMachine.maybe_end_planning(_db, s)
    assert_eq(s.phase, GameState.Phase.PLANNING)

func test_planning_ends_on_timer():
    var s := _fresh()
    s.phase_time_left = 1.0
    var ev := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.EXECUTION)
    assert_true(_types(ev).has("phase_changed"))

func test_execution_timer_leads_to_judgment_then_finished():
    var s := _fresh()
    PhaseMachine.enter_execution(s)
    s.players["p0"].ingredients = ["boeuf"]
    s.players["p1"].ingredients = ["citron"]
    s.phase_time_left = 1.0
    var ev1 := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.JUDGMENT)
    assert_true(_types(ev1).has("judged"))
    assert_true(s.result.has("winner"))
    assert_eq(s.result["winner"], "p0")   # boeuf (umami/gras) bat citron
    s.phase_time_left = 1.0
    var ev2 := PhaseMachine.advance_timers(_db, s, 2.0)
    assert_eq(s.phase, GameState.Phase.FINISHED)
    assert_true(_types(ev2).has("match_finished"))
