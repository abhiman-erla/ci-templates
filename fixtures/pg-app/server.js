// Fixture: exits unless it can open a TCP connection to the host and port in
// DATABASE_URL (db:5432 in the tests), then answers /health with 200. It does
// not speak the Postgres protocol; reaching the port is the proof.
const http = require('node:http');
const net = require('node:net');

const raw = process.env.DATABASE_URL;
if (!raw) {
  console.error('pg-app: DATABASE_URL is not set');
  process.exit(1);
}
const url = new URL(raw);
const socket = net.connect({ host: url.hostname, port: Number(url.port || 5432) });
socket.setTimeout(3000);
socket.on('error', (err) => {
  console.error(`pg-app: cannot reach ${url.hostname}:${url.port || 5432}: ${err.code || err.message}`);
  process.exit(1);
});
socket.on('timeout', () => {
  console.error('pg-app: database connection timed out');
  process.exit(1);
});
socket.on('connect', () => {
  socket.destroy();
  http
    .createServer((req, res) => {
      res.writeHead(req.url === '/health' ? 200 : 404, { 'content-type': 'text/plain' });
      res.end(req.url === '/health' ? 'ok\n' : 'not found\n');
    })
    .listen(Number(process.env.PORT || 3000), '0.0.0.0');
});
