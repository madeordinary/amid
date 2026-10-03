// Disposable listener. Never run against an existing server. No dependencies.
const net = require('node:net');
const server = net.createServer(socket => socket.end());
const memory = Buffer.alloc(16 * 1024 * 1024, 1);
server.listen(0, '127.0.0.1', () => {
  console.log(JSON.stringify({pid:process.pid,port:server.address().port,runtime:'node',project:process.cwd(),memoryBytes:memory.length}));
});
const began = Date.now();
const timer = setInterval(() => {
  const elapsed = Date.now() - began;
  if (elapsed > 1500 && elapsed < 3000) {
    const end = Date.now() + 25; while (Date.now() < end) Math.sqrt(Math.random());
  }
}, 100);
setTimeout(() => { clearInterval(timer); server.close(); }, 8000);
