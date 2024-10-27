#!/bin/bash

# Function to check for a command
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install 'expect' using Homebrew
install_expect() {
    echo "Attempting to install 'expect' using Homebrew..."
    if command_exists brew; then
        brew install expect
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install 'expect' using Homebrew."
            exit 1
        fi
    else
        echo "Error: Homebrew is not installed. Please install Homebrew or manually install 'expect'."
        exit 1
    fi
}

# Check for 'unbuffer' (from 'expect' package)
if ! command_exists unbuffer; then
    echo "'unbuffer' command not found."
    install_expect
fi

# Verify that 'unbuffer' is now installed
if ! command_exists unbuffer; then
    echo "Error: 'unbuffer' is still not available after attempted installation."
    exit 1
fi

# Check for 'osascript' (should be available on macOS)
if ! command_exists osascript; then
    echo "Error: 'osascript' command not found. This script requires 'osascript' to play system alert sounds."
    exit 1
fi

# Now proceed with the main script functionality
retries=0
max_retries=10  # Set a maximum number of retries

success=1  # Variable to track if the script was successful

while true; do
    temp_output=$(mktemp)
    
    # Run the command and capture output and exit code
    # Using 'unbuffer' to preserve colors
    unbuffer "$@" 2>&1 | tee "$temp_output"
    exit_code=${PIPESTATUS[0]}
    
    # Extract the last 10 lines
    last10=$(tail -n 10 "$temp_output")
    
    # Check for 'ERROR' in the last 10 lines
    if echo "$last10" | grep -q "ERROR"; then
        error_in_output=0
    else
        error_in_output=1
    fi
    
    rm "$temp_output"
    
    if [ $exit_code -ne 0 ] || [ $error_in_output -eq 0 ]; then
        ((retries++))
        echo -e "\nRetry #$retries\n"
        if [ $retries -ge $max_retries ]; then
            echo "Maximum retries reached. Exiting."
            success=0  # Mark as failure
            break
        fi
        sleep 1
    else
        break
    fi
done

echo -e "\nNumber of retries: $retries"

# Play system alert sound based on success or failure
if [ $success -eq 1 ]; then
    # Play success system alert sound (beep twice)
    osascript -e 'beep 2'
else
    # Play failure system alert sound (beep three times)
    osascript -e 'beep 3'
fi