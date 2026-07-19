class_name ValidContent
extends RefCounted

# Contenu brut minimal mais VALIDE, réutilisé par plusieurs suites.
static func make() -> Dictionary:
    return {
        "ingredients": [
            {"id": "tomate", "name": "Tomate", "cost": 2, "stats": {"umami": 3, "acide": 4}, "tags": ["legume"]},
            {"id": "boeuf", "name": "Bœuf", "cost": 3, "stats": {"umami": 5, "gras": 3}, "tags": ["viande"]},
            {"id": "sucre", "name": "Sucre", "cost": 1, "stats": {"sucre": 6}, "tags": ["base"]},
            {"id": "citron", "name": "Citron", "cost": 1, "stats": {"acide": 5}, "tags": ["fruit"]},
        ],
        "actions": [
            {"id": "cuire", "name": "Cuire", "base_duration_sec": 45, "effect": {"stats": {"umami": 2, "acide": -1}}},
            {"id": "mixer", "name": "Mixer", "base_duration_sec": 20, "effect": {"stats": {"texture": 3}}},
            {"id": "assaisonner", "name": "Assaisonner", "base_duration_sec": 15, "effect": {"stats": {"umami": 1, "sucre": 1}}},
        ],
        "cards": [
            {"id": "card_boost_umami", "name": "Umami+", "type": "global", "target": "self", "effect": {"stats": {"umami": 2}}},
            {"id": "card_saboter", "name": "Sabotage", "type": "contextual", "target": "opponent", "linked_action": "cuire", "effect": {"stats": {"acide": 2}}},
        ],
        "events": [
            {"id": "coupure", "name": "Coupure de courant", "trigger_window": "execution", "effect": {"rule": "delay_execution_seconds", "value": 5}},
        ],
        "criteria": [
            {"id": "umami", "weight": 1.5},
            {"id": "gras", "weight": 0.5},
        ],
        "match_config": {
            "ingredient_budget": 10,
            "ingredients_per_player": {"min": 3, "max": 6},
            "timeline_actions": {"min": 5, "max": 6},
            "deck_size": {"min": 2, "max": 20},
            "starting_hand_size": 2,
            "phase_durations": {"planning": 150, "execution": 330, "judgment": 60},
            "event_frequency_window_sec": 240,
        },
    }
