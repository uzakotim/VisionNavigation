import socket

UDP_IP = "0.0.0.0"       # listen on all interfaces
UDP_PORT = 8080          # must match the app’s port

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))

print(f"Listening for UDP packets on port {UDP_PORT}...")

while True:
    data, addr = sock.recvfrom(1024)
    msg = data.decode().strip()
    print(f"Received from {addr}: {msg}")

    # Example: parse "w 150"
    parts = msg.split()
    if len(parts) == 2:
        direction = parts[0]
        speed = int(parts[1])

        # Replace these with actual motor commands
        if direction == "w":
            print(f"→ Forward speed {speed}")
        elif direction == "s":
            print(f"→ Backward speed {speed}")
        elif direction == "e":
            print(f"→ Rotate right speed {speed}")
        elif direction == "q":
            print(f"→ Rotate left speed {speed}")
        elif direction == "k":
            print(f"→ Stop {speed}")
        else:
            print("Unknown command")
    else:
        print("Invalid command format")
