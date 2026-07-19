extends GutTest

func _criteria() -> Array:
    return [
        CriterionRes.from_dict({"id": "umami", "weight": 1.5}),
        CriterionRes.from_dict({"id": "gras", "weight": 0.5}),
    ]

func test_score_dish_weighted_sum():
    var dish := {"umami": 10, "gras": 4, "acide": 8}
    # 10*1.5 + 4*0.5 = 15 + 2 = 17 (acide non noté)
    assert_almost_eq(JudgmentEngine.score_dish(dish, _criteria()), 17.0, 0.001)

func test_unknown_criterion_scores_zero():
    var crit := [CriterionRes.from_dict({"id": "originalite", "weight": 2.0})]
    assert_almost_eq(JudgmentEngine.score_dish({"umami": 10}, crit), 0.0, 0.001)

func test_judge_picks_higher_score():
    var a := {"umami": 10}
    var b := {"umami": 4}
    var r := JudgmentEngine.judge(a, b, _criteria())
    assert_eq(r["winner"], "a")
    assert_almost_eq(r["score_a"], 15.0, 0.001)

func test_judge_draw():
    var a := {"umami": 6}
    var b := {"umami": 6}
    var r := JudgmentEngine.judge(a, b, _criteria())
    assert_eq(r["winner"], "draw")
