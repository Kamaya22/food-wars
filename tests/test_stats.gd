extends GutTest

func test_empty_has_all_keys_at_zero():
    var e := Stats.empty()
    assert_eq(e.size(), 6, "6 clés de stats")
    for k in Stats.KEYS:
        assert_eq(int(e[k]), 0, "%s doit valoir 0" % k)

func test_add_sums_key_by_key():
    var a := {"umami": 2, "gras": 1}
    var b := {"umami": 3, "acide": 4}
    var r := Stats.add(a, b)
    assert_eq(int(r["umami"]), 5)
    assert_eq(int(r["gras"]), 1)
    assert_eq(int(r["acide"]), 4)
    assert_eq(int(r["amer"]), 0, "clé absente = 0")

func test_add_does_not_mutate_inputs():
    var a := Stats.empty()
    var b := {"umami": 5}
    Stats.add(a, b)
    assert_eq(int(a["umami"]), 0, "l'entrée ne doit pas être modifiée")

func test_clamp_bounds_each_key():
    var s := {"umami": 99, "acide": -99}
    var r := Stats.clamp_stats(s, -10, 10)
    assert_eq(int(r["umami"]), 10)
    assert_eq(int(r["acide"]), -10)
