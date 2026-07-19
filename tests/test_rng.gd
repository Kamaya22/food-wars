extends GutTest

func test_same_seed_same_sequence():
    var a := Rng.new(42)
    var b := Rng.new(42)
    for i in range(20):
        assert_eq(a.randi_range(0, 1000), b.randi_range(0, 1000),
            "même seed doit produire la même séquence")

func test_different_seed_diverges():
    var a := Rng.new(1)
    var b := Rng.new(2)
    var same := true
    for i in range(20):
        if a.randi_range(0, 1000000) != b.randi_range(0, 1000000):
            same = false
    assert_false(same, "des seeds différents doivent diverger")

func test_state_roundtrip_resumes_sequence():
    var a := Rng.new(7)
    a.randi_range(0, 100)
    var snapshot := a.get_state()
    var next_a := a.randi_range(0, 100)
    var b := Rng.new(999)
    b.set_state(snapshot)
    assert_eq(b.randi_range(0, 100), next_a, "restaurer l'état reprend la séquence")
