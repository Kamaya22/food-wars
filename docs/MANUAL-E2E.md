# Food Wars — Smoke-test E2E manuel (transport réseau réel)

Vérifie le chemin socket réel que GUT ne couvre pas (`WebSocketPeer` +
relais Node). À exécuter après tout changement de `relay/` ou
`net/websocket_transport.gd`.

## Pré-requis
- Node ≥ 18, Godot 4.5 (`godot`).
- Une fois : `cd relay && npm install`.

## 1. Démarrer le relais
```bash
cd relay && npm start
# -> "Food Wars relay en écoute sur ws://localhost:8080"
```

## 2. Lancer l'hôte (terminal 2)
```bash
godot --headless -s scripts/net_smoke.gd -- host ws://localhost:8080
# -> "[host] CODE DE ROOM = XXXX"
```
✅ Attendu : un code de room à 4 caractères s'affiche.

## 3. Lancer l'invité (terminal 3), avec le code
```bash
godot --headless -s scripts/net_smoke.gd -- join ws://localhost:8080 XXXX
```
✅ Attendu :
- les deux affichent « room prête » avec la **même** seed et les rôles host/guest ;
- l'hôte joue le match et affiche « MATCH TERMINÉ — résultat: {winner:…} » ;
- l'invité affiche « vue finale reçue — phase FINISHED » ;
- les deux processus se terminent (exit 0).

## 4. Reconnexion (manuel)
- Relancer hôte + invité ; pendant que l'hôte attend/joue, tuer le process invité
  (Ctrl-C) **avant** la fin.
✅ Attendu côté relais/hôte : l'hôte ne plante pas ; un `peer_left` est routé
  (pause). Relancer l'invité avec le **même** code dans les 30 s.
✅ Attendu : l'hôte reçoit `peer_rejoined` (resync), l'invité reçoit une nouvelle
  `room_ready` et resynchronise. Au-delà de 30 s : l'invité obtient `unknown_code`
  (room fermée).

## 5. Déconnexion hôte
- Tuer l'hôte pendant une partie.
✅ Attendu : l'invité reçoit `host_left` → `session_aborted("host_disconnected")`.

## En cas d'échec
Noter le terminal fautif et le message. Le dispatch (parsing/mapping) est couvert
par `tests/test_websocket_transport.gd` et `relay/relay.test.js` ; un échec ici
pointe donc vers le vrai I/O socket (`connect_to_url`/`poll`/`send_text`) ou le
câblage `ws` de `relay/server.js`.
