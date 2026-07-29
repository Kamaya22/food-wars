# Food Wars — Relais WebSocket

Routeur de matchmaking sans logique de jeu : apparie deux joueurs dans une room
par code, désigne l'hôte, génère la seed, transfère les messages opaques.

## Lancer

```bash
cd relay
npm install        # installe `ws` (requis seulement pour exécuter le serveur)
npm start          # écoute sur ws://localhost:8080 (PORT pour changer)
```

## Tester

```bash
cd relay
npm test           # node --test — aucune installation requise (relay.js est pur)
```

## Protocole

- Contrôle (JSON avec `t`) : `create` → `created{code}` ; `join{code}` →
  `room_ready{role,seed,opponent_id}` aux deux, ou `error{reason}`.
- Reconnexion : `peer_left` / `peer_rejoined` / `room_closed` / `host_left`.
- Tout autre message (champ `kind`) est transféré verbatim au pair.
