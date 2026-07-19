class_name Rng
extends RefCounted

var _rng: RandomNumberGenerator

func _init(seed_value: int) -> void:
    _rng = RandomNumberGenerator.new()
    _rng.seed = seed_value

func randi_range(from: int, to: int) -> int:
    return _rng.randi_range(from, to)

func randf() -> float:
    return _rng.randf()

func get_state() -> int:
    return int(_rng.state)

func set_state(state: int) -> void:
    _rng.state = state
