class_name Reconciler
extends RefCounted

var _view: Dictionary = {}
var _tick_id: int = -1
var _pending: Dictionary = {}   # seq (int) -> true

func apply_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> bool:
    if tick_id <= _tick_id:
        return false
    _view = view
    _tick_id = tick_id
    for seq in _pending.keys():
        if seq <= ack_seq:
            _pending.erase(seq)
    return true

func current_view() -> Dictionary:
    return _view

func current_tick_id() -> int:
    return _tick_id

func add_pending_intent(seq: int) -> void:
    _pending[seq] = true

func pending_count() -> int:
    return _pending.size()
