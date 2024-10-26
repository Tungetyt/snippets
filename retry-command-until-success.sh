#!/bin/bash

retries=0
max_retries=10  # Set a maximum number of retries to prevent infinite loops

while true; do
    # Run the command, display output in real-time, and capture output in a temporary file
    temp_output=$(mktemp)
    "$@" 2>&1 | tee "$temp_output"
    exit_code=${PIPESTATUS[0]}  # Get exit code of the command

    # Get the last 10 lines of the output
    last10=$(tail -n 10 "$temp_output")

    # Check if "[ERROR]" exists in the last 10 lines
    if echo "$last10" | grep -q "ERROR"; then
        error_in_output=0  # Found "[ERROR]"
    else
        error_in_output=1  # Did not find "[ERROR]"
    fi

    rm "$temp_output"  # Clean up temporary file

    if [ $exit_code -ne 0 ] || [ $error_in_output -eq 0 ]; then
        # Increment retry counter if command failed or "[ERROR]" found
        ((retries++))
        echo "Retry #$retries"

        # Check if maximum retries reached
        if [ $retries -ge $max_retries ]; then
            echo "Maximum retries reached. Exiting."
            exit 1
        fi

        # Optionally, wait for a moment before retrying
        sleep 1
    else
        # Exit loop if command succeeded and no "[ERROR]" in last 10 lines
        break
    fi
done

# Print the number of retries that occurred
echo "Number of retries: $retries"