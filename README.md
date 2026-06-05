# VPN Config Management

Production-ready VPN configuration management system with Telegram bot, admin panel, automated order processing, payment verification, and config delivery.

## Features

* Telegram bot for customer interaction
* Web-based admin panel for order management
* Automatic config delivery after approval
* Shared JSON database
* Receipt upload & verification system
* SSL support with Cloudflare or Let's Encrypt
* Systemd service integration

---

# Table of Contents

* [Architecture](#architecture)
* [Quick Summary](#quick-summary)
* [One-Line Installation](#one-line-installation)
* [Manual Installation](#manual-installation)
* [SSL Configuration](#ssl-configuration)
* [Systemd Service Setup](#systemd-service-setup)
* [Configuration Files](#configuration-files)
* [Usage Flow](#usage-flow)
* [Project Structure](#project-structure)
* [Troubleshooting](#troubleshooting)
* [Security Notes](#security-notes)
* [Useful Commands](#useful-commands)
* [License](#license)

---

# Architecture

Core components:

| Component       | Technology                           |
| --------------- | ------------------------------------ |
| Telegram Bot    | Python + aiogram                     |
| Admin Panel     | PHP + Nginx                          |
| Database        | JSON (`data.json`)                   |
| Service Manager | systemd                              |
| SSL             | Cloudflare Origin CA / Let's Encrypt |

Shared data location:

```text
/var/www/vpn_project/data.json
```

---

# Quick Summary

Workflow:

1. User selects a VPN plan through Telegram bot
2. User uploads payment receipt
3. Admin reviews receipt in web panel
4. Admin approves/rejects order
5. Config is automatically delivered
6. Receipt file gets deleted after approval

---

# One-Line Installation

Run installer:

```bash
sudo bash -c "$(curl -fsSL https://github.com/THE00DAMER/vpn-config-manager/blob/main/install.sh)"
```

Installer will ask for:

* Subdomain
* Telegram bot token
* Admin IDs
* Admin password
* Panel port
* SSL certificates

The script automatically:

* Installs dependencies
* Creates directories
* Configures nginx
* Creates services
* Starts the bot

---

# Manual Installation

## 1. Update System

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Install Dependencies

```bash
sudo apt install -y nginx php-fpm php-curl python3-venv python3-pip ufw curl wget git
```

## 3. Clone Repository

```bash
git clone https://github.com/THE00DAMER/vpn-config-manager.git

cd vpn-config-manager
```

## 4. Create Project Directories

```bash
sudo mkdir -p /var/www/vpn_project/public_html/receipts

sudo cp -r ./* /var/www/vpn_project/

sudo chown -R www-data:www-data /var/www/vpn_project

sudo chmod -R 755 /var/www/vpn_project

sudo chmod 775 /var/www/vpn_project/public_html/receipts
```

## 5. Setup Python Environment

```bash
cd /var/www/vpn_project

python3 -m venv venv

source venv/bin/activate

pip install aiogram requests

deactivate
```

## 6. Configure SSL

Continue with SSL section below.

## 7. Configure Nginx

Configure nginx virtual host and restart:

```bash
sudo systemctl restart nginx
```

---

# Systemd Service Setup

Create bot service:

```bash
sudo tee /etc/systemd/system/tg_bot.service > /dev/null <<EOF
[Unit]
Description=Damer Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/vpn_project
ExecStart=/var/www/vpn_project/venv/bin/python3 /var/www/vpn_project/bot.py
ExecStop=/bin/kill -9 \$MAINPID
Restart=always
RestartSec=5
KillMode=process
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

Enable service:

```bash
sudo systemctl daemon-reload

sudo systemctl enable tg_bot

sudo systemctl start tg_bot
```

---

# SSL Configuration

## Option A: Cloudflare Origin CA

Create Origin Certificate:

Cloudflare Dashboard:

```text
SSL/TLS → Origin Server → Create Certificate
```

Save certificates:

```bash
sudo tee /etc/ssl/cert.pem > /dev/null

sudo tee /etc/ssl/key.pem > /dev/null

sudo chmod 600 /etc/ssl/cert.pem /etc/ssl/key.pem
```

Requirements:

* Create DNS A record
* Enable Cloudflare proxy
* Configure nginx SSL paths

---

## Option B: Let's Encrypt

Install certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx
```

Generate certificate:

```bash
sudo certbot certonly --standalone -d panel.yourdomain.com
```

Copy certificates:

```bash
sudo cp /etc/letsencrypt/live/panel.yourdomain.com/fullchain.pem /etc/ssl/cert.pem

sudo cp /etc/letsencrypt/live/panel.yourdomain.com/privkey.pem /etc/ssl/key.pem

sudo chmod 600 /etc/ssl/cert.pem /etc/ssl/key.pem
```

Test renewal:

```bash
sudo certbot renew --dry-run
```

---

# Configuration Files

## Telegram Bot

File:

```text
/var/www/vpn_project/bot.py
```

Edit:

```python
BOT_TOKEN = "YOUR_BOT_TOKEN"

ADMIN_IDS_STR = "123456,789012"

DATA_FILE = "/var/www/vpn_project/data.json"
```

---

## Admin Panel

File:

```text
/var/www/vpn_project/public_html/index.php
```

Edit:

```php
$admin_pass = "YourStrongPassword";

$bot_token = "YOUR_BOT_TOKEN";
```

---

## Shared Database

```text
/var/www/vpn_project/data.json
```

---

## Receipts Folder

```text
/var/www/vpn_project/public_html/receipts/
```

---

# Permissions

```bash
sudo chown -R www-data:www-data /var/www/vpn_project

sudo chmod 600 /etc/ssl/cert.pem /etc/ssl/key.pem

sudo chmod 660 /var/www/vpn_project/data.json
```

---

# Usage Flow

## User Commands

| Command    | Description     |
| ---------- | --------------- |
| `/start`   | Show plans      |
| `/buy`     | Purchase plan   |
| `/orders`  | View orders     |
| `/support` | Contact support |

---

## Admin Commands

| Command                        | Description   |
| ------------------------------ | ------------- |
| `/admin`                       | Admin help    |
| `/approve <order_id> <config>` | Approve order |
| `/reject <order_id>`           | Reject order  |
| `/stats`                       | Statistics    |

---

## Web Panel

Access:

```text
https://panel.yourdomain.com:2087
```

Features:

* Review orders
* View receipts
* Approve / reject purchases
* Send configs

---

# Project Structure

```text
/var/www/vpn_project/
├── bot.py
├── data.json
├── venv/
└── public_html/
    ├── index.php
    ├── settings.php
    └── receipts/
```

---

# Troubleshooting

## Bot Not Responding

```bash
sudo systemctl status tg_bot

sudo journalctl -u tg_bot -n 200 -f
```

---

## TelegramConflictError

```bash
sudo pkill -f bot.py

sudo systemctl restart tg_bot
```

---

## PHP Curl Error

```bash
sudo apt install php-curl -y

sudo systemctl restart php-fpm
```

---

## Check Nginx

```bash
sudo nginx -t

sudo tail -f /var/log/nginx/error.log
```

---

# Security Notes

* Keep bot tokens private
* Use strong passwords
* Limit file permissions
* Avoid running services as root
* Backup `data.json`
* Store secrets in environment variables when possible

---

# Useful Commands

View logs:

```bash
sudo journalctl -u tg_bot -f
```

Restart bot:

```bash
sudo systemctl restart tg_bot
```

Check nginx:

```bash
sudo tail -50 /var/log/nginx/error.log
```

Installed PHP modules:

```bash
php -m | grep curl
```

---

# License

MIT License

See:

```text
LICENSE
```
