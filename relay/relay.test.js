const { test } = require('node:test');
const assert = require('node:assert');
const { Relay } = require('./relay');

function fakeConn() {
    return {
        sent: [],
        closed: false,
        send(text) { this.sent.push(text); },
        close() { this.closed = true; },
        last() { return JSON.parse(this.sent[this.sent.length - 1]); },
    };
}

function newRelay() {
    // seed et code déterministes pour les tests
    let n = 0;
    return new Relay({ makeSeed: () => 4242, makeCode: () => 'WOK' + (n++) });
}

function fakeTimers() {
    const pending = [];
    return {
        setTimer: (cb, _ms) => { const h = { cb }; pending.push(h); return h; },
        clearTimer: (h) => { const i = pending.indexOf(h); if (i >= 0) pending.splice(i, 1); },
        fireAll() { const cbs = pending.splice(0); cbs.forEach((h) => h.cb()); },
        count() { return pending.length; },
    };
}

function pairedRelay(timers) {
    let n = 0;
    const r = new Relay({
        makeSeed: () => 4242, makeCode: () => 'WOK' + (n++),
        setTimer: timers.setTimer, clearTimer: timers.clearTimer, reconnectMs: 30000,
    });
    const host = fakeConn(), guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    return { r, host, guest, code };
}

test('create renvoie un code et désigne l\'hôte', () => {
    const r = newRelay();
    const host = fakeConn();
    r.onConnect(host);
    r.onMessage(host, JSON.stringify({ t: 'create' }));
    const m = host.last();
    assert.strictEqual(m.t, 'created');
    assert.strictEqual(m.code, 'WOK0');
});

test('join sur code inconnu renvoie une erreur', () => {
    const r = newRelay();
    const guest = fakeConn();
    r.onConnect(guest);
    r.onMessage(guest, JSON.stringify({ t: 'join', code: 'ZZZZ' }));
    assert.strictEqual(guest.last().t, 'error');
    assert.strictEqual(guest.last().reason, 'unknown_code');
});

test('join valide envoie room_ready aux deux avec rôles et seed', () => {
    const r = newRelay();
    const host = fakeConn();
    const guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    const hm = host.last(), gm = guest.last();
    assert.strictEqual(hm.t, 'room_ready');
    assert.strictEqual(hm.role, 'host');
    assert.strictEqual(hm.opponent_id, 'guest');
    assert.strictEqual(gm.role, 'guest');
    assert.strictEqual(gm.opponent_id, 'host');
    assert.strictEqual(hm.seed, 4242);
    assert.strictEqual(gm.seed, 4242);
});

test('join d\'une room pleine renvoie une erreur', () => {
    const r = newRelay();
    const host = fakeConn(), g1 = fakeConn(), g2 = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(g1); r.onMessage(g1, JSON.stringify({ t: 'join', code }));
    r.onConnect(g2); r.onMessage(g2, JSON.stringify({ t: 'join', code }));
    assert.strictEqual(g2.last().t, 'error');
    assert.strictEqual(g2.last().reason, 'room_full');
});

test('les messages de jeu (kind) sont transférés au pair, verbatim', () => {
    const r = newRelay();
    const host = fakeConn(), guest = fakeConn();
    r.onConnect(host); r.onMessage(host, JSON.stringify({ t: 'create' }));
    const code = host.last().code;
    r.onConnect(guest); r.onMessage(guest, JSON.stringify({ t: 'join', code }));
    const gameMsg = JSON.stringify({ kind: 'intent', seq: 1, intent: { type: 'x' } });
    r.onMessage(guest, gameMsg);           // invité -> hôte
    assert.strictEqual(host.sent[host.sent.length - 1], gameMsg);
    const snap = JSON.stringify({ kind: 'snapshot', view: {}, tick_id: 1, ack_seq: 1 });
    r.onMessage(host, snap);               // hôte -> invité
    assert.strictEqual(guest.sent[guest.sent.length - 1], snap);
});

test('déconnexion invité : l\'hôte reçoit peer_left et un minuteur est armé', () => {
    const timers = fakeTimers();
    const { r, host } = pairedRelay(timers);
    r.onClose(host._room.guest);
    assert.strictEqual(host.last().t, 'peer_left');
    assert.strictEqual(timers.count(), 1);
});

test('expiration de la fenêtre : le pair restant reçoit room_closed', () => {
    const timers = fakeTimers();
    const { r, host } = pairedRelay(timers);
    r.onClose(host._room.guest);
    timers.fireAll();
    assert.strictEqual(host.last().t, 'room_closed');
});

test('rejoin dans la fenêtre : hôte peer_rejoined, invité re-room_ready, minuteur annulé', () => {
    const timers = fakeTimers();
    const { r, host, code } = pairedRelay(timers);
    r.onClose(host._room.guest);
    const back = fakeConn();
    r.onConnect(back); r.onMessage(back, JSON.stringify({ t: 'join', code }));
    assert.strictEqual(host.last().t, 'peer_rejoined');
    assert.strictEqual(back.last().t, 'room_ready');
    assert.strictEqual(back.last().role, 'guest');
    assert.strictEqual(timers.count(), 0, 'le minuteur de reconnexion est annulé');
});

test('déconnexion hôte : l\'invité reçoit host_left et la room disparaît', () => {
    const timers = fakeTimers();
    const { r, host, guest, code } = pairedRelay(timers);
    r.onClose(host);
    assert.strictEqual(guest.last().t, 'host_left');
    assert.strictEqual(r.rooms.has(code), false);
});
