extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _player(timeline: Array) -> PlayerState:
    var p := PlayerState.new()
    p.timeline = timeline
    return p

func test_action_completes_after_its_duration():
    var p := _player(["assaisonner"])   # base_duration_sec = 15
    var done := Timeline.advance(_db, p, 10.0)
    assert_eq(done.size(), 0)
    assert_eq(p.exec_index, 0)
    done = Timeline.advance(_db, p, 10.0)
    assert_eq(done, ["assaisonner"])
    assert_eq(p.exec_index, 1)

func test_delay_pauses_progress():
    var p := _player(["assaisonner"])   # 15s
    p.exec_delay_left = 5.0
    var done := Timeline.advance(_db, p, 5.0)  # tout consommé par le délai
    assert_eq(done.size(), 0)
    assert_almost_eq(p.exec_delay_left, 0.0, 0.001)
    assert_almost_eq(p.exec_elapsed, 0.0, 0.001)

func test_multiple_actions_in_one_big_delta():
    var p := _player(["assaisonner", "mixer"])  # 15 + 20 = 35
    var done := Timeline.advance(_db, p, 40.0)
    assert_eq(done, ["assaisonner", "mixer"])
    assert_eq(p.exec_index, 2)

func test_idle_when_finished():
    var p := _player([])
    assert_eq(Timeline.advance(_db, p, 100.0).size(), 0)

func test_advance_all_emits_and_draws():
    var s := GameCore.start_match(_db, _db.match_config, 3, ["p0", "p1"])
    s.players["p0"].timeline = ["assaisonner"]
    s.players["p0"].deck = ["card_boost_umami"]
    var hand_before: int = s.players["p0"].hand.size()
    var events := Timeline.advance_all(_db, s, 20.0)
    var completed := events.filter(func(e): return e.type == "action_completed")
    var drawn := events.filter(func(e): return e.type == "card_drawn")
    assert_eq(completed.size(), 1)
    assert_eq(drawn.size(), 1)
    assert_false(drawn[0].has("card_id"))  # anti-triche : pas d'id dans l'event
    assert_eq(s.players["p0"].hand.size(), hand_before + 1)
