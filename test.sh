#!/bin/bash
# Test script for the Telegram security application
# This script runs the security application in test mode first
# and provides instructions for running in normal mode

set -e  # Exit on any error

# Check if binary exists
if [ ! -f "./deadman" ]; then
    echo "Error: deadman binary not found."
    echo "Please run the build script first: ./build-telegram-security.sh"
    exit 1
fi

# Run in test mode
echo "Running in test mode (no actual data wiping)..."
./deadman -test

echo ""
echo "Test mode completed."
echo ""
echo "If you want to run in full mode (with actual data wiping when 'No' is selected)"
echo "or if the verification times out after 120 seconds, run:"
echo "./deadman"
