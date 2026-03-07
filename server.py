#!/usr/bin/env python3
"""
Simple HTTP server for hosting MC automation files
Serves files from current directory with no caching headers
"""

import http.server
import socketserver
import os
from pathlib import Path

PORT = 8080

class NoCacheHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler that disables caching"""
    
    def end_headers(self):
        # Disable all caching
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()
    
    def log_message(self, format, *args):
        # Custom log format
        print(f"[{self.log_date_time_string()}] {format % args}")

def main():
    # Change to script directory
    os.chdir(Path(__file__).parent)
    
    with socketserver.TCPServer(("", PORT), NoCacheHTTPRequestHandler) as httpd:
        print(f"=== MC Automation File Server ===")
        print(f"Serving files from: {os.getcwd()}")
        print(f"Server running at: http://localhost:{PORT}")
        print(f"Press Ctrl+C to stop")
        print()
        
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")

if __name__ == "__main__":
    main()
