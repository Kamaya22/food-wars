extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _config() -> MatchConfigRes:
    return _db.match_config

func test_start_match_initial_state():
    var s := GameCore.start_match(_db, _config(), 123, ["p0", "p1"])
    assert_eq(s.phase, GameState.Phase.PLANNING)
    assert_eq(s.player_order, ["p0", "p1"])
    assert_eq(s.players.size(), 2)
    assert_almost_eq(s.phase_time_left, float(_config().phase_planning_sec), 0.001)
    var p0: PlayerState = s.players["p0"]
    assert_eq(p0.budget_left, _config().ingredient_budget)
    assert_eq(p0.hand.size(), _config().starting_hand_size)
    assert_eq(p0.deck.size(), _config().deck_size_max - _config().starting_hand_size)

func test_start_match_is_deterministic():
    var a := GameCore.start_match(_db, _config(), 777, ["p0", "p1"])
    var b := GameCore.start_match(_db, _config(), 777, ["p0", "p1"])
    assert_eq(a.players["p0"].hand, b.players["p0"].hand)
    assert_eq(a.players["p0"].deck, b.players["p0"].deck)

func test_start_match_different_seed_differs():
    var a := GameCore.start_match(_db, _config(), 1, ["p0", "p1"])
    var b := GameCore.start_match(_db, _config(), 2, ["p0", "p1"])
    # au moins une des deux mains diffère (extrêmement probable ; sinon deck)
    var same: bool = a.players["p0"].hand == b.players["p0"].hand and a.players["p0"].deck == b.players["p0"].deck
    assert_false(same)
