// Stands in for Render's deploy hook and a deployed service's health URL, for
// self-test only. Writes its port to PORT_FILE and each request to LOG_FILE.
//   HOOK_STATUS       status from POST /deploy/... (default 200)
//   OLD_VERSION       version in /health until REPORT_AFTER requests have been made
//   NEW_VERSION       version in /health after that
//   REPORT_AFTER      requests answered with OLD_VERSION. Omit it to never report NEW_VERSION
//   HEALTH_STATUS     status from /health (default 200)
//   HEALTH_HANG       if set, /health never answers
const fs = require('node:fs');
const http = require('node:http');

const env = process.env;
let healthRequests = 0;

const server = http.createServer((req, res) => {
  fs.appendFileSync(env.LOG_FILE, `${req.method} ${req.url}\n`);
  const path = req.url.split('?')[0];
  if (path === '/health') {
    healthRequests += 1;
    if (env.HEALTH_HANG) return;
    const reported = env.REPORT_AFTER !== undefined && healthRequests > Number(env.REPORT_AFTER);
    res.writeHead(Number(env.HEALTH_STATUS || 200), { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: reported ? env.NEW_VERSION : env.OLD_VERSION }));
    return;
  }
  if (req.method === 'POST' && path.startsWith('/deploy/')) {
    const status = Number(env.HOOK_STATUS || 200);
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(status === 200 ? '{"deploy":{"id":"dep-fake123"}}' : '{}');
    return;
  }
  res.writeHead(405);
  res.end();
});

server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(env.PORT_FILE, String(server.address().port));
});
