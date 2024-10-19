#!/bin/bash

# Exit immediately if a command exits with a non-zero status and enable error tracing
set -e
set -o pipefail

# Log file for capturing the script's output
LOGFILE="git_rebase_safe.log"

# Function to log messages with timestamps
log() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $1" | tee -a "$LOGFILE"
}

# Usage message
usage() {
    echo "Usage: $0 [options] [rebase_branch]"
    echo
    echo "Options:"
    echo "  -d, --dry-run    Perform a dry run without making any changes."
    echo "  -h, --help       Show this help message."
    echo
    echo "Arguments:"
    echo "  rebase_branch    (Optional) The branch to rebase onto. Defaults to 'origin/develop'."
    exit 1
}

# Default values
dry_run=false
rebase_branch=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$rebase_branch" ]; then
                rebase_branch="$1"
                shift
            else
                echo "Error: Unknown argument '$1'"
                usage
            fi
            ;;
    esac
done

# Fetch updates from the remote repository
log "Fetching from remote repository..."
if ! git fetch --all --prune; then
    log "Error: 'git fetch' failed."
    exit 1
fi

# Get the name of the current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$current_branch" ]; then
    log "Error: Unable to determine the current branch."
    exit 1
fi
log "Current branch is '$current_branch'."

# Generate a UTC timestamp
timestamp=$(date -u +"%Y%m%d%H%M%S")

# Create a backup of the current branch with a timestamp suffix
backup_branch="${current_branch}_backup_${timestamp}"
log "Creating backup branch '$backup_branch'."
if ! git branch "$backup_branch"; then
    log "Error: Failed to create backup branch '$backup_branch'."
    exit 1
fi

# Check for uncommitted changes and stash them if any
if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Uncommitted changes detected. Stashing changes..."
    if ! git stash push -u -m "Auto stash before safe rebase"; then
        log "Error: Failed to stash changes."
        exit 1
    fi
fi

# Determine the branch to rebase onto
if [ -n "$rebase_branch" ]; then
    original_branch="$rebase_branch"
    log "Rebasing onto specified branch '$original_branch'."
else
    # Attempt to find upstream branch
    original_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")
    if [ -z "$original_branch" ]; then
        original_branch="origin/develop"
        log "No upstream branch found. Defaulting to '$original_branch'."
    else
        log "Upstream branch is '$original_branch'."
    fi
fi

# Perform dry run if requested
if [ "$dry_run" = true ]; then
    log "Performing a dry run rebase of '$current_branch' onto '$original_branch'."
    if ! git rebase --dry-run "$original_branch"; then
        log "Error: Dry run rebase failed."
        # Restore stashed changes after dry run
        if git stash list | grep -q "Auto stash before safe rebase"; then
            log "Restoring stashed changes..."
            git stash pop || log "Warning: Failed to apply stashed changes."
        fi
        exit 1
    else
        log "Dry run rebase completed successfully. No changes were made."
        # Restore stashed changes after dry run
        if git stash list | grep -q "Auto stash before safe rebase"; then
            log "Restoring stashed changes..."
            if ! git stash pop; then
                log "Error: Failed to apply stashed changes."
                exit 1
            fi
        fi
        exit 0
    fi
fi

# Perform the rebase operation
log "Rebasing '$current_branch' onto '$original_branch'."
if ! git rebase "$original_branch"; then
    log "Error: Rebase failed. You can recover using the backup branch '$backup_branch'."
    # Restore stashed changes if rebase fails
    if git stash list | grep -q "Auto stash before safe rebase"; then
        log "Restoring stashed changes..."
        git stash pop || log "Warning: Failed to apply stashed changes."
    fi
    exit 1
fi

# Restore stashed changes after a successful rebase
if git stash list | grep -q "Auto stash before safe rebase"; then
    log "Restoring stashed changes..."
    if ! git stash pop; then
        log "Error: Failed to apply stashed changes."
        exit 1
    fi
fi

log "Rebase completed successfully."

# Suggest running tests or checks after rebasing
log "It's recommended to run your project's test suite to ensure everything works as expected."
