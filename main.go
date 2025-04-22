package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"math/big"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

// Build-time variables that will be set during compilation
var (
	// These values are injected at build time with -ldflags
	telegramAPIKey     string
	telegramChatIDStr  string // String representation of the chat ID
	timeoutSecondsStr  string // String representation of timeout in seconds
	destructiveDefault string // Whether destructive mode is the default
)

// Global flags
var (
	testMode    bool
	loginType   string
	destructive bool // Flag for destructive mode
)

// Function to generate a new SSH key pair
func generateSSHKey(username string) (string, string, error) {
	// Create a unique key filename with timestamp
	timestamp := time.Now().Format("20060102-150405")
	privateKeyPath := fmt.Sprintf("/tmp/recovery_key_%s_%s", username, timestamp)

	// Generate new SSH key with ssh-keygen
	cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-f", privateKeyPath, "-N", "", "-C",
		fmt.Sprintf("recovery-key-%s-%s", username, timestamp))

	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("failed to generate SSH key: %v", err)
	}

	// Read the private key
	privateKey, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return "", "", fmt.Errorf("failed to read private key: %v", err)
	}

	// Read the public key
	publicKey, err := os.ReadFile(privateKeyPath + ".pub")
	if err != nil {
		return "", "", fmt.Errorf("failed to read public key: %v", err)
	}

	// Clean up the files
	os.Remove(privateKeyPath)
	os.Remove(privateKeyPath + ".pub")

	return string(privateKey), string(publicKey), nil
}

// Function to generate a secure random password
func generateRandomPassword(length int) (string, error) {
	if length < 8 {
		length = 16 // Minimum secure length
	}

	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+,./<>?"
	charsetLength := big.NewInt(int64(len(charset)))

	password := make([]byte, length)
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, charsetLength)
		if err != nil {
			return "", err
		}
		password[i] = charset[n.Int64()]
	}

	return string(password), nil
}

// Function to lock down a user's account
func lockdownUser(username string) (string, string, error) {
	if testMode {
		log.Println("[TEST MODE] Would lock down user", username)
		return "test-ssh-key", "test-password", nil
	}

	// Generate new SSH key
	privateKey, publicKey, err := generateSSHKey(username)
	if err != nil {
		return "", "", err
	}

	// Generate new password
	password, err := generateRandomPassword(16)
	if err != nil {
		return "", "", fmt.Errorf("failed to generate password: %v", err)
	}

	// Get user's home directory
	userInfo, err := user.Lookup(username)
	if err != nil {
		return "", "", fmt.Errorf("failed to find user home directory: %v", err)
	}

	// Ensure .ssh directory exists
	sshDir := filepath.Join(userInfo.HomeDir, ".ssh")
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		return "", "", fmt.Errorf("failed to create .ssh directory: %v", err)
	}

	// Add new public key to authorized_keys
	authKeysPath := filepath.Join(sshDir, "authorized_keys")

	// Get existing keys
	var existingKeys []byte
	if _, err := os.Stat(authKeysPath); err == nil {
		existingKeys, _ = os.ReadFile(authKeysPath)
	}

	// Append the new key
	f, err := os.OpenFile(authKeysPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return "", "", fmt.Errorf("failed to open authorized_keys: %v", err)
	}

	// Add comment to identify this as a recovery key
	if len(existingKeys) > 0 && !bytes.HasSuffix(existingKeys, []byte("\n")) {
		f.Write([]byte("\n"))
	}
	f.Write([]byte("# Recovery key added after suspicious login\n"))
	f.Write([]byte(publicKey))
	f.Close()

	// Fix permissions
	chownCmd := exec.Command("chown", "-R", username+":"+username, sshDir)
	chownCmd.Run()

	// Change user password
	changePasswdCmd := exec.Command("chpasswd")
	changePasswdCmd.Stdin = strings.NewReader(username + ":" + password)
	if err := changePasswdCmd.Run(); err != nil {
		log.Printf("Warning: Failed to change password: %v", err)
	}

	// Kill all sessions of user
	cmd := exec.Command("pkill", "-u", username)
	cmd.Run() // Ignore errors - might not be any sessions

	// Lock system logins (will still allow SSH key login)
	lockCmd := exec.Command("usermod", "-L", username)
	if err := lockCmd.Run(); err != nil {
		log.Printf("Warning: Failed to lock password: %v", err)
	}

	return privateKey, password, nil
}

// Function to handle security action depending on mode
func handleSecurityAction(username string) error {
	if testMode {
		if destructive {
			log.Println("[TEST MODE] Would wipe user data (destructive mode)")
		} else {
			log.Println("[TEST MODE] Would lock down user account (lockdown mode)")
		}
		return nil
	}

	if !destructive {
		// Non-destructive lockdown mode
		log.Printf("Locking down user %s", username)

		// Generate new credentials and lock the account
		privateKey, password, err := lockdownUser(username)
		if err != nil {
			return fmt.Errorf("failed to lock down user: %v", err)
		}

		// Format credentials for Telegram message
		formattedKey := fmt.Sprintf("```\n%s\n```", privateKey)
		credentials := fmt.Sprintf("🔑 *New SSH Private Key:*\n%s\n\n🔐 *New Password:*\n`%s`",
			formattedKey, password)

		// Send credentials via Telegram
		chatID, _ := strconv.ParseInt(telegramChatIDStr, 10, 64)
		bot, err := tgbotapi.NewBotAPI(telegramAPIKey)
		if err == nil {
			msg := tgbotapi.NewMessage(chatID, "🔐 *ACCOUNT RECOVERY CREDENTIALS*\n\nUser account has been locked down. Use these credentials to regain access:")
			msg.ParseMode = "Markdown"
			bot.Send(msg)

			// Send credentials in a separate message
			credMsg := tgbotapi.NewMessage(chatID, credentials)
			credMsg.ParseMode = "Markdown"
			bot.Send(credMsg)

			// Send usage instructions
			instructions := "To use the new SSH key:\n1. Save the key to a file (e.g., recovery_key)\n2. Set permissions: `chmod 600 recovery_key`\n3. Connect: `ssh -i recovery_key " + username + "@hostname`"
			instMsg := tgbotapi.NewMessage(chatID, instructions)
			bot.Send(instMsg)
		}

		return nil
	} else {
		// Destructive mode - wipe user data
		log.Printf("Wiping user data for %s", username)
		cmd := exec.Command("sh", "-c", "pkill -u "+username+" && sudo userdel -r "+username)
		return cmd.Run()
	}
}

// SendLoginVerification sends a Telegram message asking for login verification
// and takes appropriate security action if they reply "no" or if timeout occurs
func SendLoginVerification() error {
	// Validate that we have the required build-time variables
	if telegramAPIKey == "" {
		return fmt.Errorf("Telegram API key not provided at build time")
	}

	if telegramChatIDStr == "" {
		return fmt.Errorf("Telegram Chat ID not provided at build time")
	}

	// Convert chat ID from string to int64
	telegramChatID, err := strconv.ParseInt(telegramChatIDStr, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid chat ID: %v", err)
	}

	// Parse timeout from string to integer with a default fallback
	timeoutSeconds := 120 // Default timeout: 120 seconds
	if timeoutSecondsStr != "" {
		parsedTimeout, err := strconv.Atoi(timeoutSecondsStr)
		if err == nil && parsedTimeout > 0 {
			timeoutSeconds = parsedTimeout
		}
	}

	// Initialize Telegram bot
	bot, err := tgbotapi.NewBotAPI(telegramAPIKey)
	if err != nil {
		return fmt.Errorf("error initializing Telegram bot: %v", err)
	}

	// Get system information
	hostname, _ := os.Hostname()
	username := os.Getenv("USER")
	if username == "" {
		// Try to get username with whoami command if env variable not available
		userCmd := exec.Command("whoami")
		userOutput, err := userCmd.Output()
		if err == nil {
			username = strings.TrimSpace(string(userOutput))
		} else {
			username = "unknown"
		}
	}

	// Get IP information if possible
	ipInfo := "unknown location"
	ipCmd := exec.Command("sh", "-c", "curl -s ifconfig.me")
	ipOutput, err := ipCmd.Output()
	if err == nil {
		ip := strings.TrimSpace(string(ipOutput))
		ipInfo = ip
	}

	// Format current time
	currentTime := time.Now().Format("2006-01-02 15:04:05 MST")

	// Use the login type in messages
	accessMethod := loginType
	if accessMethod == "" {
		accessMethod = "unknown"
	}

	// Create keyboard
	keyboard := tgbotapi.NewInlineKeyboardMarkup(
		tgbotapi.NewInlineKeyboardRow(
			tgbotapi.NewInlineKeyboardButtonData("Yes", "yes"),
			tgbotapi.NewInlineKeyboardButtonData("No", "no"),
		),
	)

	// Prepare and send message
	msg := tgbotapi.NewMessage(telegramChatID, fmt.Sprintf("Login detected for user %s on %s.\nTime: %s\nIP: %s\nAccess: %s\n\nWas this you?",
		username, hostname, currentTime, ipInfo, accessMethod))
	msg.ReplyMarkup = keyboard
	sentMsg, err := bot.Send(msg)
	if err != nil {
		return fmt.Errorf("error sending message: %v", err)
	}

	// Create a context with the configured timeout
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutSeconds)*time.Second)
	defer cancel()

	// Create update configuration
	updateConfig := tgbotapi.NewUpdate(0)
	updateConfig.Timeout = 60 // Long polling timeout in seconds

	// Start receiving updates
	updates := bot.GetUpdatesChan(updateConfig)

	// Create security action description based on mode
	var securityAction string
	if destructive {
		securityAction = "Wiping user data"
	} else {
		securityAction = "Locking down account and resetting credentials"
	}

	// Wait for response or timeout
	select {
	case update := <-updates:
		// Check if this update is a callback query (button press)
		if update.CallbackQuery != nil && update.CallbackQuery.Message.MessageID == sentMsg.MessageID {
			// Acknowledge the callback
			callbackConfig := tgbotapi.NewCallback(update.CallbackQuery.ID, "")
			bot.Request(callbackConfig)

			// Delete the original message with the buttons
			deleteMsg := tgbotapi.NewDeleteMessage(telegramChatID, sentMsg.MessageID)
			bot.Send(deleteMsg)

			// Process the response
			if update.CallbackQuery.Data == "no" {
				// Send a message that we're taking security action
				notifyMsg := tgbotapi.NewMessage(telegramChatID, "⚠️ UNAUTHORIZED LOGIN DETECTED ⚠️\n\nUser: "+username+
					"\nHost: "+hostname+
					"\nTime: "+currentTime+
					"\nIP: "+ipInfo+
					"\nAccess: "+accessMethod+
					"\n\n"+securityAction+"...")
				bot.Send(notifyMsg)

				// Take appropriate security action
				if err := handleSecurityAction(username); err != nil {
					return fmt.Errorf("failed to execute security action: %v", err)
				}
				return nil
			} else if update.CallbackQuery.Data == "yes" {
				// Confirm authorized login with detailed report
				confirmMsg := tgbotapi.NewMessage(telegramChatID, "✅ LOGIN CONFIRMED AS AUTHORIZED\n\n"+
					"User: "+username+
					"\nHost: "+hostname+
					"\nTime: "+currentTime+
					"\nIP: "+ipInfo+
					"\nAccess: "+accessMethod)
				bot.Send(confirmMsg)
				return nil
			}
		}

	case <-ctx.Done():
		// Timeout occurred

		// Delete the original message with the buttons
		deleteMsg := tgbotapi.NewDeleteMessage(telegramChatID, sentMsg.MessageID)
		bot.Send(deleteMsg)

		timeoutMsg := tgbotapi.NewMessage(telegramChatID, fmt.Sprintf("⚠️ VERIFICATION TIMEOUT (%d seconds) ⚠️\n\n", timeoutSeconds)+
			"User: "+username+
			"\nHost: "+hostname+
			"\nTime: "+currentTime+
			"\nIP: "+ipInfo+
			"\nAccess: "+accessMethod+
			"\n\nFor security, "+strings.ToLower(securityAction)+"...")
		bot.Send(timeoutMsg)

		// Take appropriate security action
		if err := handleSecurityAction(username); err != nil {
			return fmt.Errorf("failed to execute security action after timeout: %v", err)
		}
		return nil
	}

	return nil
}

func main() {
	// Parse command line flags
	testModeFlag := flag.Bool("test", false, "Run in test mode (no actual security actions)")
	loginTypeFlag := flag.String("login-type", "unknown", "Type of login (ssh, desktop)")
	destructiveFlag := flag.Bool("destructive", false, "Use destructive mode (wipe user data) instead of lockdown mode")
	flag.Parse()

	// Set global flags
	testMode = *testModeFlag
	loginType = *loginTypeFlag
	destructive = *destructiveFlag

	// Log startup information
	securityMode := "lockdown"
	if destructive {
		securityMode = "destructive"
	}

	if testMode {
		log.Printf("[TEST MODE] Running with actual Telegram messages but NO security actions (login type: %s, mode: %s)",
			loginType, securityMode)

		if timeoutSecondsStr != "" {
			log.Printf("[TEST MODE] Timeout set to %s seconds", timeoutSecondsStr)
		} else {
			log.Printf("[TEST MODE] Using default timeout (120 seconds)")
		}
	} else {
		log.Printf("Starting security check for %s login (mode: %s)", loginType, securityMode)

		if timeoutSecondsStr != "" {
			log.Printf("Timeout set to %s seconds", timeoutSecondsStr)
		}
	}

	if err := SendLoginVerification(); err != nil {
		log.Fatalf("Error: %v", err)
	}
}
