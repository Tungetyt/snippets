#!/bin/bash

retries=0

while true; do
    # Run the command and capture both output and exit code
    output=$("$@" 2>&1)
    exit_code=$?

    # Get the last 10 lines of the output
    last10=$(echo "$output" | tail -n 10)

    # Check if "[ERROR]" exists in the last 10 lines
    echo "$last10" | grep -q "[ERROR]"
    error_in_output=$?

    if [ $exit_code -ne 0 ] || [ $error_in_output -eq 0 ]; then
        # Increment retry counter if command failed or "[ERROR]" found
        ((retries++))
    else
        # Exit loop if command succeeded and no "[ERROR]" in last 10 lines
        break
    fi
done

# Display the output of the successful command run
echo "$output"

# Print the number of retries that occurred
echo "Number of retries: $retries"