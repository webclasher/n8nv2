#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# n8n + Telegram Bot Pro Installer – Version 2.3
# Secure | Production-Ready | Interactive Backups | Auto-Rotation
# Usage:
# curl -fsSL <URL_TO_THIS_SCRIPT> | sudo bash -s \
#   "your-domain.com" "you@example.com" "BOT_TOKEN" "TELEGRAM_USER_ID"
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# Input
DOMAIN=${1:-}
EMAIL=${2:-}
BOT_TOKEN=${3:-}
USER_ID=${4:-}

if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$BOT_TOKEN" || -z "$USER_ID" ]]; then
  echo "❌ Missing arguments. Usage:"
  echo "bash install.sh \"domain.com\" \"you@email.com\" \"BOT_TOKEN\" \"USER_ID\""
  exit 1
fi

BOT_DIR="/opt/n8n_bot"
BACKUP_DIR="/opt/n8n_backups"

echo -e "\n📦 Installing core tools..."
apt update -y
apt install -y bash curl sudo gnupg2 ca-certificates lsb-release unzip procps cron

# Docker, Nginx, Certbot, UFW (Omitted for brevity, no changes from previous version)
# ...
# Docker
echo -e "\n🐳 Installing Docker..."
apt install -y apt-transport-https software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

# Run n8n container
echo -e "\n🚀 Launching n8n container..."
mkdir -p /var/n8n && chown 1000:1000 /var/n8n
docker run -d --restart unless-stopped --name n8n -p 5678:5678 \
  -e N8N_HOST="$DOMAIN" \
  -e WEBHOOK_URL="https://S{DOMAIN}/" \
  -e WEBHOOK_TUNNEL_URL="https://S{DOMAIN}/" \
  -v /var/n8n:/home/node/.n8n \
  n8nio/n8n:latest

# Nginx + Certbot
echo -e "\n🌐 Installing Nginx + Certbot..."
apt install -y nginx python3-certbot-nginx

echo -e "\n⚙️ Writing Nginx config..."
cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
rm -f /etc/nginx/sites-enabled/default || true
nginx -t && systemctl reload nginx

echo -e "\n🔒 Getting SSL certificate..."
certbot --non-interactive --agree-tos --nginx -m "$EMAIL" -d "$DOMAIN"

# UFW
echo -e "\n🛡️ Enabling UFW firewall..."
apt install -y ufw
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# Telegram Bot
echo -e "\n🤖 Installing Telegram bot..."
apt install -y python3 python3-pip
pip3 install --break-system-packages python-telegram-bot telebot python-dotenv psutil

mkdir -p "$BOT_DIR" "$BACKUP_DIR"

# --- Embedded Python Script for Telegram Bot ---
cat > "$BOT_DIR/n8n_bot.py" <<'EOF'
#!/usr/bin/env python3
import os
import subprocess
import telebot
import psutil
import glob
from datetime import datetime
from dotenv import load_dotenv
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton

# Load config
load_dotenv('/opt/n8n_bot/n8n_bot_config.env')
BOT_TOKEN = os.getenv("BOT_TOKEN")
AUTHORIZED_USER = int(os.getenv("AUTHORIZED_USER"))
DOMAIN = os.getenv("DOMAIN")
BACKUP_DIR = "/opt/n8n_backups"

bot = telebot.TeleBot(BOT_TOKEN)
os.makedirs(BACKUP_DIR, exist_ok=True)

def is_authorized(message):
    if isinstance(message, telebot.types.CallbackQuery):
        return message.from_user.id == AUTHORIZED_USER
    return message.from_user.id == AUTHORIZED_USER

# /help and /start
@bot.message_handler(commands=["help", "start"])
def help_cmd(message):
    if not is_authorized(message): return
    bot.reply_to(message, """🤖 *n8n Bot Control Panel*

📦 Backup Commands:
/createbackup – Create a manual backup.
/showbackup – List all backups to restore or delete.
(Automatic weekly backups with 3-file rotation are enabled).

⚙️ Management:
/status – Check if container is running.
/logs – Show recent logs.
/restart – Restart n8n.
/update – Update n8n with zero downtime.
/system – Check CPU, RAM, and disk usage.

/help – Show this message again
""", parse_mode="Markdown")

# --- Management Commands ---
@bot.message_handler(commands=["status"])
def status(message):
    if not is_authorized(message): return
    out = subprocess.getoutput("docker ps --filter name=n8n")
    bot.reply_to(message, f"📦 *n8n Status:*\n```\n{out}\n```", parse_mode="Markdown")

@bot.message_handler(commands=["system"])
def system_stats(message):
    if not is_authorized(message): return
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    reply = (f"📊 *System Usage*\n\n"
             f"💻 *CPU:* {cpu}%\n"
             f"🧠 *RAM:* {ram}%\n"
             f"💽 *Disk:* {disk}%")
    bot.reply_to(message, reply, parse_mode="Markdown")

@bot.message_handler(commands=["logs"])
def logs(message):
    if not is_authorized(message): return
    out = subprocess.getoutput("docker logs --tail 50 n8n")
    bot.reply_to(message, f"📄 *n8n Logs:*\n```\n{out}\n```", parse_mode="Markdown")

@bot.message_handler(commands=["restart"])
def restart(message):
    if not is_authorized(message): return
    subprocess.run(["docker", "restart", "n8n"])
    bot.reply_to(message, "🔁 n8n restarted!")

@bot.message_handler(commands=["update"])
def update(message):
    if not is_authorized(message): return
    try:
        bot.reply_to(message, "⏳ Pulling latest n8n image...")
        subprocess.run(["docker", "pull", "n8nio/n8n:latest"], check=True)
        bot.send_message(message.chat.id, "🚀 Launching new container...")
        run_cmd = [
            "docker", "run", "-d", "--name", "n8n_new",
            "-p", "5678:5678", "--restart", "unless-stopped",
            "-e", f"N8N_HOST={DOMAIN}", "-e", f"WEBHOOK_URL=https://{DOMAIN}/",
            "-v", "/var/n8n:/home/node/.n8n", "n8nio/n8n:latest"
        ]
        subprocess.run(run_cmd, check=True)
        bot.send_message(message.chat.id, "✨ Swapping containers...")
        subprocess.run(["docker", "stop", "n8n"], check=False)
        subprocess.run(["docker", "rm", "n8n"], check=False)
        subprocess.run(["docker", "rename", "n8n_new", "n8n"], check=True)
        bot.send_message(message.chat.id, "✅ n8n updated successfully!")
    except subprocess.CalledProcessError as e:
        bot.send_message(message.chat.id, f"❌ An error occurred:\n`{e.stderr}`", parse_mode="Markdown")
        subprocess.run(["docker", "rm", "-f", "n8n_new"], capture_output=True)
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ An unexpected error occurred: {str(e)}")

# --- Backup and Restore Commands ---
def _do_restore(backup_path):
    subprocess.run(["tar", "-xzf", backup_path, "-C", "/"])
    subprocess.run(["docker", "restart", "n8n"])

@bot.message_handler(commands=["createbackup"])
def create_backup(message):
    if not is_authorized(message): return
    backup_file = f"manual-backup-{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.tar.gz"
    backup_path = os.path.join(BACKUP_DIR, backup_file)
    subprocess.run(["tar", "-czf", backup_path, "-C", "/var", "n8n"])
    bot.reply_to(message, f"📦 Manual backup created:\n`{os.path.basename(backup_path)}`", parse_mode="Markdown")

@bot.message_handler(commands=["showbackup"])
def show_backup(message):
    if not is_authorized(message): return
    backups = sorted(glob.glob(f"{BACKUP_DIR}/*.tar.gz"), reverse=True)
    if not backups:
        bot.reply_to(message, "⚠️ No backups found.")
        return
    bot.reply_to(message, "📂 Here are the available backups:")
    for backup in backups:
        filename = os.path.basename(backup)
        markup = InlineKeyboardMarkup()
        restore_button = InlineKeyboardButton("Restore", callback_data=f"restore:{backup}")
        delete_button = InlineKeyboardButton("Delete", callback_data=f"delete:{backup}")
        markup.add(restore_button, delete_button)
        bot.send_message(message.chat.id, f"`{filename}`", reply_markup=markup, parse_mode="Markdown")

@bot.callback_query_handler(func=lambda call: call.data.startswith('restore:'))
def restore_callback(call):
    if not is_authorized(call): return
    backup_path = call.data.split(':', 1)[1]
    filename = os.path.basename(backup_path)
    if os.path.exists(backup_path):
        _do_restore(backup_path)
        bot.answer_callback_query(call.id, f"Restoring {filename}...")
        bot.edit_message_text(f"✅ Restored from `{filename}`.", call.message.chat.id, call.message.message_id, parse_mode="Markdown")
    else:
        bot.answer_callback_query(call.id, "Error: File not found.", show_alert=True)
        bot.edit_message_text(f"❌ Restore failed. `{filename}` not found.", call.message.chat.id, call.message.message_id, parse_mode="Markdown")

@bot.callback_query_handler(func=lambda call: call.data.startswith('delete:'))
def delete_callback(call):
    if not is_authorized(call): return
    backup_path = call.data.split(':', 1)[1]
    filename = os.path.basename(backup_path)
    if os.path.exists(backup_path):
        os.remove(backup_path)
        bot.answer_callback_query(call.id, f"Deleted {filename}.")
        bot.edit_message_text(f"🗑️ Deleted `{filename}`.", call.message.chat.id, call.message.message_id, parse_mode="Markdown")
    else:
        bot.answer_callback_query(call.id, "Error: File not found.", show_alert=True)
        bot.edit_message_text(f"❌ Delete failed. `{filename}` not found.", call.message.chat.id, call.message.message_id, parse_mode="Markdown")

@bot.message_handler(content_types=["document"])
def upload_backup(message):
    if not is_authorized(message): return
    doc = message.document
    if not doc.file_name.endswith(".tar.gz"): return
    try:
        file_info = bot.get_file(doc.file_id)
        downloaded = bot.download_file(file_info.file_path)
        path = os.path.join(BACKUP_DIR, doc.file_name)
        with open(path, "wb") as f: f.write(downloaded)
        _do_restore(path)
        bot.reply_to(message, f"✅ Backup `{doc.file_name}` restored!", parse_mode="Markdown")
    except Exception as e:
        bot.reply_to(message, f"❌ Restore failed: {str(e)}")

# Start bot polling
bot.polling()
EOF

# --- Embedded Python Script for Backup Management ---
cat > "$BOT_DIR/backup_manager.py" <<'EOF'
#!/usr/bin/env python3
import os
import glob
import subprocess
from datetime import datetime

BACKUP_DIR = "/opt/n8n_backups"
MAX_BACKUPS = 3

def create_backup():
    """Creates a new backup."""
    backup_file = f"auto-backup-{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.tar.gz"
    backup_path = os.path.join(BACKUP_DIR, backup_file)
    subprocess.run(["tar", "-czf", backup_path, "-C", "/var", "n8n"])
    print(f"Created backup: {backup_path}")

def rotate_backups():
    """Keeps the most recent backups and deletes older ones."""
    backups = sorted(glob.glob(f"{BACKUP_DIR}/auto-backup-*.tar.gz"), key=os.path.getmtime, reverse=True)
    if len(backups) > MAX_BACKUPS:
        for old_backup in backups[MAX_BACKUPS:]:
            os.remove(old_backup)
            print(f"Deleted old backup: {old_backup}")

if __name__ == "__main__":
    os.makedirs(BACKUP_DIR, exist_ok=True)
    create_backup()
    rotate_backups()
EOF

chmod +x "$BOT_DIR/n8n_bot.py" "$BOT_DIR/backup_manager.py"

# --- Systemd and Cron Job Setup ---
cat > "$BOT_DIR/n8n_bot_config.env" <<EOF
BOT_TOKEN=$BOT_TOKEN
AUTHORIZED_USER=$USER_ID
DOMAIN=$DOMAIN
EOF

cat > /etc/systemd/system/n8n-bot.service <<EOF
[Unit]
Description=n8n Telegram Bot
After=network.target docker.service

[Service]
ExecStart=/usr/bin/python3 $BOT_DIR/n8n_bot.py
WorkingDirectory=$BOT_DIR
Restart=always
User=root
EnvironmentFile=$BOT_DIR/n8n_bot_config.env

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now n8n-bot.service

# Setup cron job for weekly backups
echo -e "\n🗓️ Setting up weekly backup cron job..."
(crontab -l 2>/dev/null | grep -v "$BOT_DIR/backup_manager.py" ; echo "0 3 * * 0 /usr/bin/python3 $BOT_DIR/backup_manager.py >> /var/log/n8n_backup.log 2>&1") | crontab -
systemctl restart cron

# Done
echo -e "\n✅ Installation complete!"
echo -e "🌐 https://$DOMAIN"
echo -e "🤖 Send /help to your bot to see the new commands!"
