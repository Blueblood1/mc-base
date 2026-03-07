---
inclusion: always
---

# CDN Server Configuration

## Server Details

- **File**: `server.py`
- **Port**: 8080
- **IP Address**: `127.0.0.1` (localhost)

## Critical Rule

When providing wget commands for ComputerCraft, ALWAYS use `127.0.0.1` as the server IP address.

**CORRECT:**
```lua
wget run http://127.0.0.1:8080/test_bundled_cable.lua
```

**WRONG:**
```lua
wget run http://YOUR_IP:8080/test_bundled_cable.lua
wget run http://YOUR_SERVER_IP:8080/test_bundled_cable.lua
```

## Why 127.0.0.1?

The CDN server runs on the same machine as the Minecraft server, so ComputerCraft computers can access it via localhost (127.0.0.1). There is no need for the user to substitute their IP address.

## Usage Pattern

When creating wget commands:
1. Always use `http://127.0.0.1:8080/filename.lua`
2. Never use placeholders like YOUR_IP or YOUR_SERVER_IP
3. The user's setup has the CDN server and MC server on the same machine

## Starting the Server

```bash
python server.py
```

The server will display various IP addresses, but for ComputerCraft wget commands, always use `127.0.0.1:8080`.
