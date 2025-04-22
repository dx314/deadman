#!/bin/bash
# Build script for Deadman Security
# Loads configuration from deadman.conf or environment variables

set -e  # Exit on any error

# Default values
OUTPUT_BINARY="deadman"
CONFIG_FILE="deadman.conf"
DEFAULT_TIMEOUT=120

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BOLD}${BLUE}Deadman Security Build Script${NC}\n"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is required but not installed${NC}"
    echo "Please install Go: https://golang.org/doc/install"
    exit 1
fi

# Initialize Go module if needed
if [ ! -f "go.mod" ]; then
    echo -e "${YELLOW}Initializing Go module...${NC}"
    go mod init deadman
fi

# Install required dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
go get github.com/go-telegram-bot-api/telegram-bot-api/v5

# Load configuration from file if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Loading configuration from $CONFIG_FILE${NC}"
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}Config file $CONFIG_FILE not found, checking environment variables${NC}"
fi

# Check for credentials from environment or config file
if [ -z "$TELEGRAM_API_KEY" ]; then
    echo -e "${YELLOW}TELEGRAM_API_KEY not found in config or environment${NC}"
    echo -e "${BLUE}Enter your Telegram API key:${NC} "
    read -r TELEGRAM_API_KEY
fi

if [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo -e "${YELLOW}TELEGRAM_CHAT_ID not found in config or environment${NC}"
    echo -e "${BLUE}Enter your Telegram chat ID:${NC} "
    read -r TELEGRAM_CHAT_ID
fi

if [ -z "$TIMEOUT_SECONDS" ]; then
    echo -e "${YELLOW}TIMEOUT_SECONDS not found, using default ($DEFAULT_TIMEOUT seconds)${NC}"
    TIMEOUT_SECONDS=$DEFAULT_TIMEOUT
fi

# Validate credentials
if [ -z "$TELEGRAM_API_KEY" ] || [ "$TELEGRAM_API_KEY" = "your_telegram_bot_token" ]; then
    echo -e "${RED}Error: Valid Telegram API key is required${NC}"
    exit 1
fi

if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" = "your_chat_id" ]; then
    echo -e "${RED}Error: Valid Telegram chat ID is required${NC}"
    exit 1
fi

echo -e "${GREEN}Using configuration:${NC}"
echo -e "  Telegram API Key: ${TELEGRAM_API_KEY:0:5}... (truncated for security)"
echo -e "  Telegram Chat ID: $TELEGRAM_CHAT_ID"
echo -e "  Timeout: $TIMEOUT_SECONDS seconds"

# Save configuration if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}Creating config file $CONFIG_FILE${NC}"
    cat > "$CONFIG_FILE" << EOL
TELEGRAM_API_KEY="$TELEGRAM_API_KEY"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
TIMEOUT_SECONDS=$TIMEOUT_SECONDS
EOL
    chmod 600 "$CONFIG_FILE"  # Secure permissions
fi

# Build the application
echo -e "\n${BLUE}Building application...${NC}"
LDFLAGS="-X main.telegramAPIKey=$TELEGRAM_API_KEY -X main.telegramChatIDStr=$TELEGRAM_CHAT_ID -X main.timeoutSecondsStr=$TIMEOUT_SECONDS"

go build -ldflags "$LDFLAGS" -o "$OUTPUT_BINARY"


if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Build successful!${NC}"
    echo -e "Binary created at ./$OUTPUT_BINARY"
    echo -e "\nTo run in test mode (no actual data wiping):"
    echo -e "  ./$OUTPUT_BINARY -test"
    echo -e "\nTo run in normal mode (with actual data wiping):"
    echo -e "  ./$OUTPUT_BINARY"
    echo -e "\nTo install system-wide:"
    echo -e "  sudo ./install-deadman-security.sh --user $(whoami)"
else
    echo -e "\n${RED}❌ Build failed!${NC}"
    exit 1
fi
