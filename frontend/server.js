const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const buildDir = path.join(__dirname, 'build');
const sslDir = path.join(__dirname, '..', 'backend', 'src', 'main', 'resources', 'ssl');

const HTTP_PORT = process.env.FE_HTTP_PORT || 3000;
const HTTPS_PORT = process.env.FE_HTTPS_PORT || 3001;

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.eot': 'application/vnd.ms-fontobject',
  '.map': 'application/json',
  '.txt': 'text/plain',
};

function handle(req, res) {
  const pathname = req.url.split('?')[0];
  let filePath = path.join(buildDir, pathname === '/' ? 'index.html' : pathname);

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(buildDir, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  res.setHeader('Content-Type', mime[ext] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-cache');
  fs.createReadStream(filePath).pipe(res);
}

function listen(server, basePort, label, ssl) {
  let port = basePort;
  const tryPort = () => {
    server.once('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        if (port - basePort >= 50) {
          console.error(`${label}: no free port found near ${basePort}.`);
          process.exit(1);
        }
        port += 1;
        console.warn(`${label}: port ${port - 1} busy, trying ${port}...`);
        tryPort();
      } else {
        throw err;
      }
    });
    server.listen(port, () => {
      console.log(`${label}: ${ssl ? 'https' : 'http'}://localhost:${port}`);
    });
  };
  tryPort();
}

listen(http.createServer(handle), HTTP_PORT, 'Frontend HTTP', false);

const keyFile = path.join(sslDir, 'localhost.key');
const certFile = path.join(sslDir, 'localhost.pem');
if (fs.existsSync(keyFile) && fs.existsSync(certFile)) {
  const options = {
    key: fs.readFileSync(keyFile),
    cert: fs.readFileSync(certFile),
  };
  listen(https.createServer(options, handle), HTTPS_PORT, 'Frontend HTTPS', true);
} else {
  console.warn('SSL certs not found, HTTPS disabled. Generate them with mkcert (see README).');
}