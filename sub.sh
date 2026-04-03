#!/bin/bash

USER=$(echo "$REQUEST_URI" | sed 's|/sub/||')

# Validate username
if ! echo "$USER" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    echo "Content-Type: text/plain"
    echo ""
    echo "Invalid username"
    exit 1
fi

CACHE="/var/www/html/subs/$USER.txt"

# Serve from cache if available
if [ -f "$CACHE" ]; then
    echo "Content-Type: text/plain"
    echo "Access-Control-Allow-Origin: *"
    echo ""
    cat "$CACHE"
    exit 0
fi

# Fetch from both upstream servers
SUB1=$(curl -s "https://server1.example.com:2096/sub/VPN1/$USER")
SUB2=$(curl -s "https://server2.example.com:2096/sub/VPN2/$USER")
RESULT=$(echo "$SUB1$SUB2" | base64 -d)

echo "$RESULT" > "$CACHE"

echo "Content-Type: text/plain"
echo "Access-Control-Allow-Origin: *"
echo ""
echo "$RESULT"
