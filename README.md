# Deadman Security

A lightweight login security system that sends Telegram notifications when someone logs into your system, allowing you to confirm or deny the login attempt.

## Features

- Detects both SSH and desktop logins
- Sends a Telegram notification with detailed login information
- Interactive "Yes"/"No" buttons to confirm login legitimacy
- Two security modes:
  - **Lockdown Mode (Default)**: Secures the account without data loss, generates new credentials
  - **Destructive Mode**: Wipes user data completely (classic "deadman switch")
- Configurable timeout period

## How It Works

When someone logs into your system:

1. Deadman sends a Telegram message with login details (user, hostname, IP, time, login type)
2. You respond with "Yes" (authorized) or "No" (unauthorized)
3. If you respond "No" or don't respond within the timeout period:
   - **In Lockdown Mode**: The system locks the account, resets password, creates a new SSH key, and sends recovery credentials to your Telegram
   - **In Destructive Mode**: The system completely wipes the user account and data

## Installation

### Prerequisites

- Go 1.15+
- A Telegram bot token and chat ID

### Building

1. Clone the repository:
   ```
   git clone https://github.com/dx314/deadman.git
   cd deadman-security
   ```

2. Create configuration file `deadman.conf`:
   ```
   TELEGRAM_API_KEY="your_telegram_bot_token"
   TELEGRAM_CHAT_ID="your_chat_id"
   TIMEOUT_SECONDS=120
   ```

3. Build the application:
   ```
   ./build.sh
   ```

### Installation

Use the included installer script:

```bash
# Install for both SSH and desktop logins
sudo ./install-deadman-security.sh --user yourusername

# Install for SSH only (useful for servers)
sudo ./install-deadman-security.sh --ssh-only
```

## Configuration

Edit `deadman.conf` to customize:

- `TELEGRAM_API_KEY`: Your Telegram bot token
- `TELEGRAM_CHAT_ID`: Your Telegram chat ID
- `TIMEOUT_SECONDS`: How long to wait for a response before taking action (default: 120)

## Security Modes

### Lockdown Mode (Default)

When an unauthorized login is detected:
- Kills all user sessions
- Locks password authentication
- Creates a new SSH key
- Resets the user password
- Sends recovery credentials via Telegram

This mode preserves all user data while securing the account.

### Destructive Mode

When an unauthorized login is detected:
- Completely removes the user account and all data
- No recovery possible

Enable with the `-destructive` flag.

## Testing

Test the system without risking data loss:

```bash
./deadman -test
```

This sends a real Telegram message but doesn# Deadman Security

A lightweight login security system that sends Telegram notifications when someone logs into your system, allowing you to confirm or deny the login attempt.

## Features

- Detects both SSH and desktop logins
- Sends a Telegram notification with detailed login information
- Interactive "Yes"/"No" buttons to confirm login legitimacy
- Wipes user data if login is unauthorized or verification times out
- Configurable timeout period

## How It Works

When someone logs into your system:

1. Deadman sends a Telegram message with login details (user, hostname, IP, time, login type)
2. You respond with "Yes" (authorized) or "No" (unauthorized)
3. If you respond "No" or don't respond within the timeout period, Deadman wipes the user data

## Installation

### Prerequisites

- Go 1.15+
- A Telegram bot token and chat ID

### Building

1. Clone the repository:
   ```
   git clone https://github.com/dx314/deadman.git
   cd deadman-security
   ```

2. Create configuration file `deadman.conf`:
   ```
   TELEGRAM_API_KEY="your_telegram_bot_token"
   TELEGRAM_CHAT_ID="your_chat_id"
   TIMEOUT_SECONDS=120
   ```

3. Build the application:
   ```
   ./build.sh
   ```

### Installation

Use the included installer script:

```bash
# Install for both SSH and desktop logins
sudo ./install-deadman-security.sh --user yourusername

# Install for SSH only (useful for servers)
sudo ./install-deadman-security.sh --ssh-only
```

## Configuration

Edit `deadman.conf` to customize:

- `TELEGRAM_API_KEY`: Your Telegram bot token
- `TELEGRAM_CHAT_ID`: Your Telegram chat ID
- `TIMEOUT_SECONDS`: How long to wait for a response before taking action (default: 120)

## Testing

Test the system without risking data loss:

```bash
./deadman -test
```

This sends a real Telegram message but doesn't actually wipe data when triggered.

## Troubleshooting

- **SSH login not detected**: Check `/var/log/auth.log` and ensure user is in `AllowUsers` in sshd_config
- **Desktop login not detected**: Check systemd service with `systemctl --user status deadman-security`
- **Telegram not connecting**: Verify API key and chat ID in configuration

## Uninstalling

```bash
sudo ./install-deadman-security.sh --uninstall
```

## Security Considerations

- Test thoroughly before deploying
- Use with caution - this can delete user data when triggered
- Consider using test mode (-test) during initial setup

## License

MIT
