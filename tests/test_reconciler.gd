extends GutTest

func test_first_snapshot_is_accepted():
    var r := Reconciler.new()
    assert_eq(r.current_tick_id(), -1)
    assert_true(r.apply_snapshot({"phase": 0}, 1, 0))
    assert_eq(r.current_view(), {"phase": 0})
    assert_eq(r.current_tick_id(), 1)

func test_newer_tick_wins():
    var r := Reconciler.new()
    r.apply_snapshot({"v": 1}, 1, 0)
    assert_true(r.apply_snapshot({"v": 2}, 2, 0))
    assert_eq(r.current_view(), {"v": 2})

func test_stale_or_equal_tick_is_ignored():
    var r := Reconciler.new()
    r.apply_snapshot({"v": 2}, 2, 0)
    assert_false(r.apply_snapshot({"v": 1}, 1, 0), "tick plus ancien ignoré")
    assert_false(r.apply_snapshot({"v": 9}, 2, 0), "tick égal ignoré")
    assert_eq(r.current_view(), {"v": 2})

func test_ack_clears_pending_intents_up_to_seq():
    var r := Reconciler.new()
    r.add_pending_intent(1)
    r.add_pending_intent(2)
    r.add_pending_intent(3)
    assert_eq(r.pending_count(), 3)
    r.apply_snapshot({}, 1, 2)   # ack_seq=2 → purge 1 et 2
    assert_eq(r.pending_count(), 1)

func test_rejected_intent_rolls_back_via_ack():
    # Un intent rejeté est quand même "acké" (l'hôte l'a traité) → il quitte la file d'attente.
    var r := Reconciler.new()
    r.add_pending_intent(5)
    r.apply_snapshot({"authoritative": true}, 1, 5)
    assert_eq(r.pending_count(), 0)
    assert_eq(r.current_view(), {"authoritative": true})

func test_stale_snapshot_does_not_clear_pending():
    var r := Reconciler.new()
    r.apply_snapshot({}, 5, 0)
    r.add_pending_intent(1)
    r.apply_snapshot({}, 3, 1)   # périmé → aucun effet
    assert_eq(r.pending_count(), 1)
