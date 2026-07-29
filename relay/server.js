'use strict';

const { WebSocketServer } = require('ws');
const { Relay } = require('./relay');

const port = Number(process.env.PORT || 8080);
const relay = new Relay();
const wss = new WebSocketServer({ port });

wss.on('connection', (ws) => {
    const conn = { send: (t) => ws.send(t), close: () => ws.close() };
    relay.onConnect(conn);
    ws.on('message', (data) => relay.onMessage(conn, data.toString()));
    ws.on('close', () => relay.onClose(conn));
});

console.log(`Food Wars relay en écoute sur ws://localhost:${port}`);
