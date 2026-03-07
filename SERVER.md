# Local Development Server

The local server allows you to test updates without GitHub's 5-minute cache delay.

## Starting the Server

```bash
python server.py
```

The server will run on `http://localhost:8080` and serve files from the current directory with no caching.

## How It Works

Both the installer and updater check the local server first:
1. Try `http://localhost:8080/path/to/file` with a 2-second timeout
2. If local server responds, use it
3. If local server is unavailable, fallback to GitHub

This means:
- During development: Run the server locally for instant updates
- In production: No server needed, automatically uses GitHub

## Testing Updates

1. Start the server: `python server.py`
2. Make changes to your files
3. Run update on your ComputerCraft devices
4. They'll pull from localhost instantly (no cache delay)

## Production Deployment

In production, just don't run the server. The installer and updater will automatically fallback to GitHub.
