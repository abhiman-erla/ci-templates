// Healthy only when SMOKE_FLAG=on, so the boot test proves smoke-env is passed through.
const http = require('node:http');

const port = Number(process.env.PORT || 3000);
http
  .createServer((req, res) => {
    if (req.url === '/healthz' && process.env.SMOKE_FLAG === 'on') {
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end(`ok ${process.env.APP_VERSION || 'unknown'}\n`);
    } else {
      res.writeHead(503);
      res.end('not ready\n');
    }
  })
  .listen(port, '0.0.0.0');
