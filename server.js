const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const N8N_WEBHOOK  = 'https://benitech-n8n.x3t6qy.easypanel.host/webhook/painel-rp';
const N8N_METRICS  = 'https://benitech-n8n.x3t6qy.easypanel.host/webhook/painel-rp-metricas';
const N8N_DISPAROS = 'https://benitech-n8n.x3t6qy.easypanel.host/webhook/disparos';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function proxyToN8N(req, res, targetUrl) {
  const url = new URL(targetUrl || N8N_WEBHOOK);
  const options = {
    hostname: url.hostname,
    port: 443,
    path: url.pathname + url.search,
    method: req.method,
    headers: { 'Content-Type': 'application/json' },
  };

  const proxyReq = https.request(options, (proxyRes) => {
    let body = '';
    proxyRes.on('data', (chunk) => (body += chunk));
    proxyRes.on('end', () => {
      res.writeHead(proxyRes.statusCode, {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
      });
      res.end(body);
    });
  });

  proxyReq.on('error', (err) => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Proxy error', detail: err.message }));
  });

  if (req.method === 'POST' || req.method === 'PATCH' || req.method === 'PUT') {
    let data = '';
    req.on('data', (chunk) => (data += chunk));
    req.on('end', () => {
      proxyReq.write(data);
      proxyReq.end();
    });
  } else {
    proxyReq.end();
  }
}

function serveStatic(req, res) {
  let filePath = req.url === '/' ? '/index.html' : req.url;
  filePath = path.join(__dirname, filePath);

  const ext = path.extname(filePath);
  const contentType = MIME[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  });
}

const server = http.createServer((req, res) => {
  // Proxy API requests to N8N
  if (req.url.startsWith('/api/')) {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
      res.end();
      return;
    }
    // Rota disparos — repassa query string para o N8N
    if (req.url.startsWith('/api/disparos')) {
      const qs = req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
      const target = new URL(N8N_DISPAROS);
      target.search = qs;
      proxyToN8N(req, res, target.toString());
    } else if (req.url.startsWith('/api/metricas')) {
      proxyToN8N(req, res, N8N_METRICS);
    } else {
      proxyToN8N(req, res);
    }
    return;
  }

  // Serve static files
  serveStatic(req, res);
});

server.listen(PORT, () => {
  console.log(`Painel RP rodando em http://localhost:${PORT}`);
});
