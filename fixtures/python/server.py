"""Owned finite-lived loopback listener; no external packages or payload reads."""
import socket, os, json, time, math
server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen(8)
memory = bytearray(16 * 1024 * 1024)
for i in range(0, len(memory), 4096): memory[i] = 1
print(json.dumps(dict(pid=os.getpid(), port=server.getsockname()[1], runtime='python', project=os.getcwd(), memoryBytes=len(memory))), flush=True)
began = time.monotonic()
while time.monotonic() - began < 8:
    elapsed = time.monotonic() - began
    if 1.5 < elapsed < 3:
        end = time.monotonic() + .025
        while time.monotonic() < end: math.sqrt(12345)
    time.sleep(.075)
server.close()
