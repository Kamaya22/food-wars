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
