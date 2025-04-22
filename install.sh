#!/bin/bash
# Deadman Security Installation Script
# This script installs the Deadman security notification system
# with options for SSH, GDM, or both

set -e  # Exit on any error

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.cto.bot"
BINARY_NAME="deadman"
SOURCE_BINARY="./deadman"  # Assumes it's in current directory
SSH_ONLY=false
GDM_USER=""

# Function to display script usage
show_usage() {
    echo -e "${BOLD}Usage:${NC} $0 [options]"
    echo -e "${BOLD}Options:${NC}"
    echo "  -h, --help          Show this help message"
    echo "  -s, --ssh-only      Install for SSH logins only (useful for servers)"
    echo "  -u, --user USER     Install for GDM login for specified user"
    echo "  -b, --binary PATH   Path to deadman binary (default: ./deadman)"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 --user alex                # Install for both SSH and GDM logins for user 'alex'"
    echo "  $0 --ssh-only                 # Install for SSH logins only"
    echo "  $0 --binary /path/to/deadman  # Use specific binary location"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        -s|--ssh-only)
            SSH_ONLY=true
            shift
            ;;
        -u|--user)
            GDM_USER="$2"
            shift 2
            ;;
        -b|--binary)
            SOURCE_BINARY="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown option: $1"
            show_usage
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error:${NC} This script must be run as root (with sudo)"
    exit 1
fi

# Check if source binary exists
if [ ! -f "$SOURCE_BINARY" ]; then
    echo -e "${RED}Error:${NC} Deadman binary not found at $SOURCE_BINARY"
    echo "Please build the binary first or specify its location with --binary"
    exit 1
fi

# Welcome message
echo -e "${BOLD}${BLUE}=======================================${NC}"
echo -e "${BOLD}${BLUE}  Deadman Security Installation Script  ${NC}"
echo -e "${BOLD}${BLUE}=======================================${NC}"
echo

# Install the binary
echo -e "${BOLD}${GREEN}[1/4] Installing binary...${NC}"
install -v -m 755 "$SOURCE_BINARY" "$INSTALL_DIR/$BINARY_NAME"
echo -e "✅ Installed $BINARY_NAME to $INSTALL_DIR\n"

# Create SSH login script
echo -e "${BOLD}${GREEN}[2/4] Setting up SSH login detection...${NC}"
cat > "$INSTALL_DIR/ssh_login_script.sh" << 'EOL'
#!/bin/bash
# Only run for actual SSH logins, not for every terminal
if [ "$PAM_TYPE" = "open_session" ]; then
  # Check if this is a real login, not just a new terminal
  if [ "$PAM_SERVICE" = "sshd" ]; then
    logger -t deadman-security "Detected SSH login for $PAM_USER, triggering security check"
    sudo -u "$PAM_USER" "$INSTALL_DIR/deadman" -login-type=ssh &
  fi
fi
EOL

# Replace INSTALL_DIR placeholder with actual path
sed -i "s|\$INSTALL_DIR|$INSTALL_DIR|g" "$INSTALL_DIR/ssh_login_script.sh"
chmod 755 "$INSTALL_DIR/ssh_login_script.sh"

# Create a backup of SSH PAM config
cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
echo -e "📄 Created backup of SSH PAM config at /etc/pam.d/sshd.bak"

# Add our script to PAM configuration
if grep -q "pam_exec.so.*ssh_login_script.sh" /etc/pam.d/sshd; then
    echo -e "⚠️ PAM configuration already contains our script, skipping modification"
else
    echo -e "session optional pam_exec.so seteuid $INSTALL_DIR/ssh_login_script.sh" >> /etc/pam.d/sshd
    echo -e "✅ Added script to SSH PAM configuration"
fi

# Update AllowUsers in sshd_config if needed
if grep -q "^AllowUsers" /etc/ssh/sshd_config; then
    echo -e "\n${YELLOW}Note:${NC} Your SSH config contains an AllowUsers directive."
    echo -e "If you cannot connect with a user, you may need to add them to AllowUsers in /etc/ssh/sshd_config"
    echo -e "Current AllowUsers: $(grep "^AllowUsers" /etc/ssh/sshd_config)"
fi

# Restart SSH service
systemctl restart ssh
echo -e "✅ SSH configuration completed and service restarted\n"

# Set up GDM login if not SSH only and user specified
if [ "$SSH_ONLY" = false ] && [ -n "$GDM_USER" ]; then
    echo -e "${BOLD}${GREEN}[3/4] Setting up GDM login detection for user $GDM_USER...${NC}"
    
    # Check if user exists
    if ! id "$GDM_USER" &>/dev/null; then
        echo -e "${RED}Error:${NC} User $GDM_USER does not exist, skipping GDM setup"
    else
        # Create systemd user directory if needed
        USER_HOME=$(eval echo ~$GDM_USER)
        USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
        mkdir -p "$USER_SYSTEMD_DIR"
        
        # Create systemd service file
        cat > "$USER_SYSTEMD_DIR/deadman-security.service" << EOL
[Unit]
Description=Security check on desktop login
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BINARY_NAME -login-type=desktop

[Install]
WantedBy=graphical-session.target
EOL
        
        # Set proper ownership
        chown -R "$GDM_USER":"$GDM_USER" "$USER_SYSTEMD_DIR"
        
        # Enable the service for the user
        sudo -u "$GDM_USER" XDG_RUNTIME_DIR=/run/user/$(id -u "$GDM_USER") systemctl --user enable deadman-security.service
        
        echo -e "✅ GDM login detection set up for user $GDM_USER"
        echo -e "📄 Service file created at $USER_SYSTEMD_DIR/deadman-security.service\n"
    fi
else
    if [ "$SSH_ONLY" = true ]; then
        echo -e "${YELLOW}Skipping GDM setup as --ssh-only was specified${NC}\n"
    elif [ -z "$GDM_USER" ]; then
        echo -e "${YELLOW}Skipping GDM setup as no user was specified (use --user)${NC}\n"
    fi
fi

# Final notes and instructions
echo -e "${BOLD}${GREEN}[4/4] Installation complete${NC}"
echo -e "${BOLD}${BLUE}=======================================${NC}"
echo -e "${BOLD}Testing Instructions:${NC}"
echo -e "1. SSH login test: From another machine, try: ${YELLOW}ssh ${GDM_USER:-your_username}@$(hostname)${NC}"
if [ "$SSH_ONLY" = false ] && [ -n "$GDM_USER" ]; then
    echo -e "2. GDM login test: Log out and log back in to your desktop session"
fi
echo
echo -e "${BOLD}Troubleshooting:${NC}"
echo -e "• Check SSH logs:    ${YELLOW}sudo journalctl -u ssh${NC}"
echo -e "• Check PAM logs:    ${YELLOW}sudo cat /var/log/auth.log | grep deadman${NC}"
echo -e "• Check service:     ${YELLOW}systemctl --user status deadman-security${NC}"
echo -e "• Run manual test:   ${YELLOW}$INSTALL_DIR/$BINARY_NAME -test${NC}"
echo
echo -e "${BOLD}To uninstall:${NC}"
echo -e "• Restore SSH PAM:   ${YELLOW}sudo cp /etc/pam.d/sshd.bak /etc/pam.d/sshd${NC}"
echo -e "• Remove GDM service:${YELLOW}systemctl --user disable deadman-security.service${NC}"
echo -e "• Remove binary:     ${YELLOW}sudo rm $INSTALL_DIR/$BINARY_NAME $INSTALL_DIR/ssh_login_script.sh${NC}"
echo -e "${BOLD}${BLUE}=======================================${NC}"
