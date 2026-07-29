'use strict';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans I,O,0,1

function defaultMakeCode() {
    let s = '';
    for (let i = 0; i < 4; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
    return s;
}

class Relay {
    constructor(opts = {}) {
        this.reconnectMs = opts.reconnectMs ?? 30000;
        this.setTimer = opts.setTimer ?? setTimeout;
        this.clearTimer = opts.clearTimer ?? clearTimeout;
        this.makeSeed = opts.makeSeed ?? (() => Math.floor(Math.random() * 2147483647));
        this.makeCode = opts.makeCode ?? defaultMakeCode;
        this.rooms = new Map(); // code -> { code, host, guest, seed, timer }
    }

    onConnect(conn) {
        conn._room = null;
        conn._role = null;
    }

    onMessage(conn, text) {
        let msg;
        try { msg = JSON.parse(text); } catch (_) { return; }
        if (msg && typeof msg.t === 'string') {
            this._control(conn, msg);
        } else {
            this._forward(conn, text);
        }
    }

    _control(conn, msg) {
        switch (msg.t) {
            case 'create': return this._create(conn);
            case 'join': return this._join(conn, String(msg.code || ''));
            default: return;
        }
    }

    _create(conn) {
        let code = this.makeCode();
        while (this.rooms.has(code)) code = this.makeCode();
        const room = { code, host: conn, guest: null, seed: this.makeSeed(), timer: null };
        this.rooms.set(code, room);
        conn._room = room;
        conn._role = 'host';
        this._send(conn, { t: 'created', code });
    }

    _join(conn, code) {
        const room = this.rooms.get(code);
        if (!room) return this._send(conn, { t: 'error', reason: 'unknown_code' });
        if (room.guest) return this._send(conn, { t: 'error', reason: 'room_full' });
        // Nouvel invité OU reprise d'un invité déconnecté (room.guest === null).
        const isRejoin = room.timer !== null;
        if (isRejoin) { this.clearTimer(room.timer); room.timer = null; }
        room.guest = conn;
        conn._room = room;
        conn._role = 'guest';
        this._send(conn, { t: 'room_ready', role: 'guest', seed: room.seed, opponent_id: 'host' });
        if (isRejoin) {
            if (room.host) this._send(room.host, { t: 'peer_rejoined' });
        } else {
            this._send(room.host, { t: 'room_ready', role: 'host', seed: room.seed, opponent_id: 'guest' });
        }
    }

    _forward(conn, text) {
        const room = conn._room;
        if (!room) return;
        const peer = conn._role === 'host' ? room.guest : room.host;
        if (peer) peer.send(text);
    }

    _send(conn, obj) {
        conn.send(JSON.stringify(obj));
    }

    onClose(conn) {
        const room = conn._room;
        if (!room) return;
        if (conn._role === 'host') {
            // Déconnexion hôte = terminale.
            if (room.timer) { this.clearTimer(room.timer); room.timer = null; }
            if (room.guest) this._send(room.guest, { t: 'host_left' });
            this.rooms.delete(room.code);
            return;
        }
        // Déconnexion invité : fenêtre de reconnexion.
        room.guest = null;
        if (room.host) this._send(room.host, { t: 'peer_left' });
        room.timer = this.setTimer(() => {
            room.timer = null;
            if (room.host) this._send(room.host, { t: 'room_closed' });
            this.rooms.delete(room.code);
        }, this.reconnectMs);
    }
}

module.exports = { Relay };
