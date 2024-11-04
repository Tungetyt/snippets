#!/bin/bash

# Exit immediately if a command exits with a non-zero status and enable error tracing
set -e
set -o pipefail

# Default log file
LOGFILE="git_rebase_safe.log"

# Function to log messages with timestamps
log() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%S%Z") $1" | tee -a "$LOGFILE"
}

# Usage message
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --base-branch BRANCH   Specify the base branch to rebase onto (default is 'origin/develop')."
    echo "  -d, --dry-run              Perform a dry run without making any changes."
    echo "  -h, --help                 Show this help message."
    echo
    exit 1
}

# Default values
dry_run=false
base_branch="origin/develop"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--base-branch)
            if [[ -n $2 ]]; then
                base_branch="$2"
                shift 2
            else
                echo "Error: --base-branch requires a branch name."
                usage
            fi
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            usage
            ;;
    esac
done

# Get the name of the current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$current_branch" ] || [ "$current_branch" == "HEAD" ]; then
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

# Fetch updates from the remote repository
log "Fetching from remote repository..."
if ! git fetch --all --prune; then
    log "Error: 'git fetch' failed."
    exit 1
fi

# Rebase onto the remote counterpart of the current branch
remote_branch="origin/$current_branch"
if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
    log "Rebasing '$current_branch' onto its remote counterpart '$remote_branch'."
    if [ "$dry_run" = true ]; then
        if ! git rebase --dry-run "$remote_branch"; then
            log "Error: Dry run rebase onto '$remote_branch' failed."
            exit 1
        else
            log "Dry run rebase onto '$remote_branch' successful."
        fi
    else
        if ! git rebase "$remote_branch"; then
            log "Error: Rebase onto '$remote_branch' failed."
            exit 1
        fi
    fi
else
    log "No remote counterpart for '$current_branch'. Skipping rebase onto remote."
fi

# Rebase onto the specified base branch
log "Rebasing '$current_branch' onto base branch '$base_branch'."
if [ "$dry_run" = true ]; then
    if ! git rebase --dry-run "$base_branch"; then
        log "Error: Dry run rebase onto '$base_branch' failed."
        exit 1
    else
        log "Dry run rebase onto '$base_branch' successful."
    fi
else
    if ! git rebase "$base_branch"; then
        log "Error: Rebase onto '$base_branch' failed."
        exit 1
    fi
fi

# Restore stashed changes after rebasing
if git stash list | grep -q "Auto stash before safe rebase"; then
    log "Restoring stashed changes..."
    if ! git stash pop; then
        log "Error: Failed to apply stashed changes."
        exit 1
    fi
fi

log "Rebase of '$current_branch' completed successfully."

# Suggest running tests or checks after rebasing
log "It's recommended to run your project's test suite to ensure everything works as expected."

# Optionally, push the current rebased branch to the remote repository
while true; do
    read -p "Do you want to push the rebased current branch '$current_branch' to the remote repository? (y/N): " push_response
    push_response=${push_response:-N}
    case $push_response in
        [Yy]* )
            log "Pushing rebased branch '$current_branch' to remote repository..."
            if ! git push --force-with-lease origin "$current_branch"; then
                log "Error: Failed to push rebased branch '$current_branch' to remote."
                exit 1
            fi
            log "Rebased branch '$current_branch' pushed successfully."
            break
            ;;
        [Nn]* )
            log "Rebased branch not pushed to remote."
            break
            ;;
        * )
            echo "Please answer yes or no."
            ;;
    esac
done