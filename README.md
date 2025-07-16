

-----

# n8n Telegram Bot & Production Installer

A single bash script to deploy a production-ready **n8n** instance on a fresh Debian/Ubuntu server. The installer includes a powerful **Telegram Bot** for easy management, backups, and updates right from your phone.

-----

## Features

  - 🚀 **One-Line Deployment**: Sets up a complete n8n environment with a single command.
  - 🐳 **Dockerized**: Runs n8n in a Docker container for isolation and easy management.
  - 🔒 **Secure by Default**:
      - Configures **Nginx** as a reverse proxy.
      - Automatically obtains and renews **Let's Encrypt SSL** certificates.
      - Enables the **UFW firewall** with minimal required ports.
  - 🤖 **Powerful Telegram Bot**: Manage your n8n instance from anywhere:
      - **Zero-Downtime Updates**: Update n8n without interrupting service.
      - **Interactive Backups**: List, restore, or delete individual backup files.
      - **Automatic Backups**: Weekly backups are created automatically with a 3-week rotation.
      - **System Monitoring**: Check server CPU, RAM, and disk usage on demand.

-----

## Prerequisites

Before you begin, ensure you have the following:

1.  A fresh server running **Debian 11/12** or **Ubuntu 22.04+**.
2.  A **domain name** (`your-domain.com`) with its A record pointing to your server's IP address.
3.  A **Telegram Bot Token**. You can get one by talking to [@BotFather](https://t.me/BotFather) on Telegram.
4.  Your personal **Telegram User ID**. You can get this from a bot like [@userinfobot](https://t.me/userinfobot).

-----

## 🚀 Installation

For security, it is highly recommended to download the script, review its contents, and then execute it.

1.  **Download the script:**

    ```bash
    curl -o install.sh -fsSL https://raw.githubusercontent.com/webclasher/n8nv2/refs/heads/main/install.sh
    ```

2.  **Run the installer:**
    Replace the placeholders with your actual domain, email, bot token, and user ID.

    ```bash
    sudo bash install.sh \
      "your-domain.com" \
      "you@example.com" \
      "YOUR_TELEGRAM_BOT_TOKEN" \
      "YOUR_TELEGRAM_USER_ID"
    ```

    ```

    curl -fsSL https://raw.githubusercontent.com/webclasher/n8nv2/refs/heads/main/install.sh | sudo bash -s "your-domain.com" "you@example.com" "YOUR_TELEGRAM_BOT_TOKEN" "YOUR_TELEGRAM_USER_ID"



The script will handle everything else. Once complete, you can access your n8n instance at `https://your-domain.com` and start talking to your bot on Telegram.

-----

## 🤖 Bot Commands

Send `/help` to your bot at any time to see this list.

### Management Commands

  * **/start** or **/help**: Shows the list of all available commands.
  * **/status**: Checks if the n8n Docker container is running.
  * **/system**: Checks the server's current CPU, RAM, and disk usage percentage.
  * **/logs**: Shows the last 50 lines of the n8n container logs.
  * **/restart**: Restarts the n8n container.
  * **/update**: Updates the n8n container to the latest version with zero downtime.

### Backup & Restore Commands

  * **/createbackup**: Creates a new manual backup of the n8n data.
  * **/showbackup**: Lists all available backups with interactive **Restore** and **Delete** buttons.
  * **File Upload**: Restore a backup by sending a `.tar.gz` file directly to the bot.

-----

## 📁 File Structure

The installer organizes files in the following locations:

  - `/opt/n8n_bot/`: Contains the bot script (`n8n_bot.py`), the weekly backup script (`backup_manager.py`), and the configuration file (`n8n_bot_config.env`).
  - `/opt/n8n_backups/`: Default storage location for all manual and automatic backups.
  - `/var/n8n/`: The persistent Docker volume where all of n8n's data is stored.
  - `/etc/systemd/system/n8n-bot.service`: The systemd service file that keeps the bot running.
  - **Cron Job**: A weekly cron job is added to run the `backup_manager.py` script.
