# Local Development Server

The local server allows you to test updates without GitHub's 5-minute cache delay.

## ComputerCraft Configuration

Before using the local server, you need to allow localhost in ComputerCraft's HTTP whitelist.

Edit your ComputerCraft config file (usually in `config/computercraft-server.toml` or `config/computercraft.cfg`):

### For CC: Tweaked (newer versions)
```toml
[[http.rules]]
    host = "127.0.0.1"
    action = "allow"

[[http.rules]]
    host = "localhost"
    action = "allow"
```

### For older ComputerCraft versions
```
http {
    whitelist=*
    # Or specifically:
    # whitelist=127.0.0.1
    # whitelist=localhost
}
```

After editing the config, restart your Minecraft server/world.

## Starting the Server

```bash
python server.py
```

The server will run on `http://localhost:8080` and serve files from the current directory with no caching.

## How It Works

Both the installer and updater check the local server first:
1. Try `http://localhost:8080/path/to/file`
2. If local server responds, use it
3. If local server is unavailable or not permitted, fallback to GitHub

This means:
- During development: Run the server locally for instant updates
- In production: No server needed, automatically uses GitHub

## Testing Updates

1. Configure ComputerCraft to allow localhost (see above)
2. Restart your Minecraft server/world
3. Start the server: `python server.py`
4. Make changes to your files
5. Run update on your ComputerCraft devices
6. They'll pull from localhost instantly (no cache delay)

## Production Deployment

In production, just don't run the server. The installer and updater will automatically fallback to GitHub.

## Troubleshooting

If you see "Domain not permitted":
- Check your ComputerCraft config has localhost whitelisted
- Restart your Minecraft server after config changes
- In-game, run `http.checkURL("http://localhost:8080")` to test

