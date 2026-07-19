class_name Intents
extends RefCounted

const ADD_INGREDIENT := "add_ingredient"
const REMOVE_INGREDIENT := "remove_ingredient"
const ADD_ACTION := "add_action"
const REMOVE_ACTION := "remove_action"
const SET_READY := "set_ready"
const PLAY_CARD := "play_card"

static func _ok() -> Dictionary:
    return {"ok": true, "error": ""}

static func _err(msg: String) -> Dictionary:
    return {"ok": false, "error": msg}

static func _is_id(v) -> bool:
    return typeof(v) == TYPE_STRING and (v as String).length() > 0

static func validate_shape(intent: Dictionary) -> Dictionary:
    if not intent.has("type") or typeof(intent["type"]) != TYPE_STRING:
        return _err("intent sans 'type' chaîne")
    var t: String = intent["type"]
    match t:
        ADD_INGREDIENT:
            return _ok() if _is_id(intent.get("ingredient_id")) else _err("ingredient_id requis")
        REMOVE_INGREDIENT, REMOVE_ACTION:
            return _ok() if typeof(intent.get("index")) == TYPE_INT else _err("index entier requis")
        ADD_ACTION:
            return _ok() if _is_id(intent.get("action_id")) else _err("action_id requis")
        SET_READY:
            return _ok() if typeof(intent.get("ready")) == TYPE_BOOL else _err("ready booléen requis")
        PLAY_CARD:
            if not _is_id(intent.get("card_id")):
                return _err("card_id requis")
            if intent.has("target_player_id") and not _is_id(intent.get("target_player_id")):
                return _err("target_player_id invalide")
            return _ok()
        _:
            return _err("type d'intent inconnu: %s" % t)
