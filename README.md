# VPN Subscription Server

Automatically serves VPN subscription configs via nginx + bash. When a client hits the URL, nginx runs a CGI script that fetches configs from two upstream servers, merges them, and returns the result. Output is cached on disk for instant subsequent responses.

---

## How It Works

```
Client (Happ) → https://domain.com/sub/username
                        ↓
                     nginx
                        ↓
              cache file exists?
               ↙ yes        ↘ no
          serve file     fcgiwrap → sub.sh
                                ↓
                      curl → server 1
                      curl → server 2
                                ↓
                      merge + decode base64
                                ↓
                      save to cache → return to client
```

---

## Requirements

- Ubuntu 22.04 / 24.04
- nginx
- fcgiwrap
- curl
- bash

---

## Installation

### 1. Install dependencies

```bash
apt update
apt install nginx fcgiwrap curl -y
```

### 2. Create directories

```bash
mkdir -p /var/www/html/subs
mkdir -p /var/www/html/cgi-bin
chown -R www-data:www-data /var/www/html/subs
```

### 3. Copy the script

```bash
cp sub.sh /var/www/html/cgi-bin/sub.sh
chmod +x /var/www/html/cgi-bin/sub.sh
chown www-data:www-data /var/www/html/cgi-bin/sub.sh
```

### 4. Configure nginx

Add to your server block (port 443):

```nginx
location ~ ^/sub/([a-zA-Z0-9_-]+)$ {
    include fastcgi_params;
    fastcgi_pass unix:/var/run/fcgiwrap.socket;
    fastcgi_param SCRIPT_FILENAME /var/www/html/cgi-bin/sub.sh;
    fastcgi_param REQUEST_URI $request_uri;
    default_type text/plain;
    add_header Access-Control-Allow-Origin *;
}
```

### 5. Start fcgiwrap and reload nginx

```bash
systemctl enable fcgiwrap
systemctl start fcgiwrap
nginx -t && systemctl reload nginx
```

---

## Script — sub.sh

```bash
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
```

> Replace `server1.example.com` and `server2.example.com` with your actual server addresses.

---

## Usage

### Add subscription in Happ or any other client

```
https://your-domain.com/sub/USERNAME
```

First request — script runs and generates the cache (~1-2 sec).  
All subsequent requests — nginx serves the file instantly from cache.

### Generate a file manually

```bash
curl https://your-domain.com/sub/username
```

---

## Cache Management

Cache files are stored in `/var/www/html/subs/`. To auto-clear, add a cron job:

```bash
crontab -e
```

```
# Clear cache every 6 hours
0 */6 * * * find /var/www/html/subs/ -name "*.txt" -delete
```

Or remove a single user's cache:

```bash
rm /var/www/html/subs/username.txt
```

---

## File Structure

```
/var/www/html/
├── cgi-bin/
│   └── sub.sh          # CGI script
└── subs/
    ├── user1.txt       # cached config for user1
    ├── user2.txt       # cached config for user2
    └── ...
```

---

## Troubleshooting

**502 Bad Gateway** — likely two conflicting server blocks in nginx config:
```bash
grep -r "server_name your-domain.com" /etc/nginx/
ls /etc/nginx/sites-enabled/
```

**404 on first request** — check that fcgiwrap is running:
```bash
systemctl status fcgiwrap
ls -la /var/run/fcgiwrap.socket
```

**Empty response** — check directory permissions:
```bash
chown -R www-data:www-data /var/www/html/subs
chmod 755 /var/www/html/subs
```
