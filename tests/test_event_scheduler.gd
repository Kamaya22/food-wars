extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _exec_state() -> GameState:
    var s := GameCore.start_match(_db, _db.match_config, 9, ["p0", "p1"])
    s.phase = GameState.Phase.EXECUTION
    s.players["p0"].stat_modifiers = Stats.empty()
    s.players["p1"].stat_modifiers = Stats.empty()
    return s

func test_no_fire_before_window_elapses():
    var s := _exec_state()
    s.event_timer_left = 100.0
    var events := EventScheduler.tick(_db, s, 10.0)
    assert_eq(events.size(), 0)
    assert_almost_eq(s.event_timer_left, 90.0, 0.001)

func test_fires_when_window_elapses():
    var s := _exec_state()
    s.event_timer_left = 5.0
    # le seul event fixture ("coupure") a trigger_window=execution, rule delay 5s
    var events := EventScheduler.tick(_db, s, 5.0)
    var fired := events.filter(func(e): return e.type == "event_fired")
    assert_eq(fired.size(), 1)
    assert_eq(fired[0].event_id, "coupure")
    assert_almost_eq(s.players["p0"].exec_delay_left, 5.0, 0.001)
    assert_almost_eq(s.players["p1"].exec_delay_left, 5.0, 0.001)
    assert_true(s.event_timer_left > 0.0)  # réarmé

func test_deterministic_same_seed():
    var a := _exec_state(); a.event_timer_left = 1.0
    var b := _exec_state(); b.event_timer_left = 1.0
    var ea := EventScheduler.tick(_db, a, 1.0)
    var eb := EventScheduler.tick(_db, b, 1.0)
    assert_eq(ea.size(), eb.size())
    assert_eq(a.players["p0"].exec_delay_left, b.players["p0"].exec_delay_left)

func test_no_events_for_phase_still_rearms():
    var s := _exec_state()
    s.phase = GameState.Phase.PLANNING  # aucun event fixture en planning
    s.event_timer_left = 1.0
    var events := EventScheduler.tick(_db, s, 1.0)
    assert_eq(events.filter(func(e): return e.type == "event_fired").size(), 0)
    assert_true(s.event_timer_left > 0.0)
