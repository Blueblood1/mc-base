# Local Development Server

The local server allows you to test updates without GitHub's 5-minute cache delay.

## Setup

1. Run the server to get your network IP:
```bash
python server.py
```

The server will display something like:
```
Network access: http://192.168.1.100:8080
```

2. Update the LOCAL_SERVER in your scripts with this IP address:
   - Edit `installer/install.lua` line 10
   - Edit `libs/updater.lua` line 7
   
   Change from:
   ```lua
   LOCAL_SERVER = "http://localhost:8080"
   ```
   
   To (use YOUR IP from the server output):
   ```lua
   LOCAL_SERVER = "http://192.168.1.100:8080"
   ```

3. Add your IP to ComputerCraft's HTTP whitelist in the config file:

### For CC: Tweaked
Edit `config/computercraft-server.toml`:
```toml
[[http.rules]]
    host = "192.168.1.100"
    action = "allow"
```

4. Restart your Minecraft server

## Testing

In ComputerCraft, test connectivity:
```lua
http.get("http://192.168.1.100:8080/VERSION")
```

If it returns a response, you're good to go!

## How It Works

Both the installer and updater try the local server first, then fallback to GitHub if unavailable.

## Production

In production, just don't run the server. Scripts automatically fallback to GitHub.

