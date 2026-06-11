const http = require("http");
const fs = require("fs");
const path = require("path");

const root = __dirname;
const port = Number(process.env.PORT || 4173);

const types = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".sql": "text/plain; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

function send(response, status, body, type = "text/plain; charset=utf-8") {
  response.writeHead(status, {
    "Content-Type": type,
    "X-Content-Type-Options": "nosniff",
  });
  response.end(body);
}

function resolveRequest(url) {
  const pathname = decodeURIComponent(new URL(url, `http://localhost:${port}`).pathname);
  const safePath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  let filePath = path.join(root, safePath);

  if (!filePath.startsWith(root)) return null;
  if (pathname.endsWith("/")) filePath = path.join(filePath, "index.html");
  return filePath;
}

const server = http.createServer((request, response) => {
  const filePath = resolveRequest(request.url);
  if (!filePath) {
    send(response, 403, "Forbidden");
    return;
  }

  fs.stat(filePath, (statError, stats) => {
    if (statError) {
      send(response, 404, "Not found");
      return;
    }

    const target = stats.isDirectory() ? path.join(filePath, "index.html") : filePath;
    fs.readFile(target, (readError, body) => {
      if (readError) {
        send(response, 404, "Not found");
        return;
      }

      send(response, 200, body, types[path.extname(target)] || "application/octet-stream");
    });
  });
});

server.listen(port, () => {
  console.log(`Misc Projects listening on ${port}`);
});
