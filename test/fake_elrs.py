import socket
import struct
import time

HOST = "127.0.0.1"
PORT = 11000
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

# Beacon like an ELRS TX module (the game will answer with HTTP, which is fine
# to fail in this offline QA; the UDP stream is what we are testing).
for _ in range(10):
    sock.sendto(b"ELRS", (HOST, PORT))
    time.sleep(0.05)

end = time.time() + 60.0
while time.time() < end:
    # 16 channels, 15-bit values.  CH1..4 centered, CH5 low (disarmed).
    values = [16384, 16384, 16000, 16384] + [16384] * 12
    packet = bytes([1, 16]) + b"".join(struct.pack("<H", v) for v in values)
    sock.sendto(packet, (HOST, PORT))
    time.sleep(0.004)
