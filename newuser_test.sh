#!/bin/bash
# Test script for the Telegram security application using a temporary user
# This script requires root privileges to create a temporary user
# It uses the existing build.sh script to build the application

set -e  # Exit on any error

# Configuration
TEST_USER="tempuser"
ORIGINAL_BINARY="./deadman"
TEST_DIR="/tmp/deadman_test"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check if the binary exists
if [ ! -f "$ORIGINAL_BINARY" ]; then
  # Try to build it
  echo "Binary not found. Attempting to build with ./build.sh..."

  if [ ! -f "./build.sh" ]; then
    echo "Error: build.sh script not found. Please build the application first."
    exit 1
  fi

  ./build.sh

  if [ ! -f "$ORIGINAL_BINARY" ]; then
    echo "Error: Failed to build the application. Please check build.sh script."
    exit 1
  fi
fi

# Function to clean up on exit
cleanup() {
  echo "Cleaning up..."

  # Kill any running processes by the temp user
  pkill -u "$TEST_USER" || true

  # Delete the temp user
  if id "$TEST_USER" &>/dev/null; then
    userdel -r "$TEST_USER" || true
    echo "Temporary user $TEST_USER removed"
  fi

  # Remove the test directory
  rm -rf "$TEST_DIR" || true

  echo "Cleanup completed"
}

# Register the cleanup function to be called on script exit
trap cleanup EXIT

echo "=== Telegram Security Test with Temporary User ==="

echo "Creating temporary user: $TEST_USER"
# Create a temporary user
useradd -m "$TEST_USER" || { echo "Failed to create user"; exit 1; }

# Create test directory and copy the binary
mkdir -p "$TEST_DIR"
cp "$ORIGINAL_BINARY" "$TEST_DIR/"

# Change ownership of the test directory and its contents
chown -R "$TEST_USER:$TEST_USER" "$TEST_DIR"

# Run the application in test mode as the temporary user
echo "Running application in test mode as temporary user $TEST_USER..."
sudo -u "$TEST_USER" "$TEST_DIR/deadman" -test

echo ""
echo "Test mode completed successfully!"
echo ""
echo "If you want to run in full mode (with actual data wiping when 'No' is selected)"
echo "you need to run this command BEFORE exiting this script with Ctrl+C:"
echo ""
echo "    sudo -u $TEST_USER $TEST_DIR/deadman"
echo ""
echo "WARNING: Running in full mode will delete the $TEST_USER account if 'No' is selected"
echo "or if the verification times out after 120 seconds"
echo ""
echo "The temporary user and test directory will be cleaned up when you exit this script with Ctrl+C."
echo "Press Ctrl+C to exit and clean up... OR run the full test command above before exiting."
tail -f /dev/null
