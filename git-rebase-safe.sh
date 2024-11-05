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
    echo "  -b, --base-branch BRANCH     Specify the base branch to rebase onto (default is 'origin/develop')."
    echo "  -r, --rebase-remote          Rebase onto the remote counterpart of the current branch."
    echo "  -B, --rebase-base            Rebase onto the specified base branch."
    echo "  -s, --skip-remote            Skip rebasing onto the remote counterpart."
    echo "  -S, --skip-base              Skip rebasing onto the base branch."
    echo "  -d, --dry-run                Perform a dry run without making any changes."
    echo "  -v, --verbose                Enable verbose output."
    echo "  -h, --help                   Show this help message."
    echo
    exit 1
}

# Default values
dry_run=false
base_branch="origin/develop"
rebase_remote=true
rebase_base=true
verbose=false

# Summary of actions
actions_taken=()

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
        -r|--rebase-remote)
            rebase_remote=true
            shift
            ;;
        -B|--rebase-base)
            rebase_base=true
            shift
            ;;
        -s|--skip-remote)
            rebase_remote=false
            shift
            ;;
        -S|--skip-base)
            rebase_base=false
            shift
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -v|--verbose)
            verbose=true
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

# Enable verbose output if requested
if [ "$verbose" = true ]; then
    set -x
fi

# Get the name of the current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$current_branch" ] || [ "$current_branch" == "HEAD" ]; then
    log "Error: Unable to determine the current branch."
    exit 1
fi
log "Current branch is '$current_branch'."

# Fetch updates from the remote repository
log "Fetching from remote repository..."
if ! git fetch --all --prune; then
    log "Error: 'git fetch' failed."
    exit 1
fi

# Function to check if rebasing onto remote counterpart is needed
needs_rebase_remote() {
    local branch="$1"
    local remote_branch="origin/$branch"

    if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
        local local_commit
        local remote_commit
        local_commit=$(git rev-parse "$branch")
        remote_commit=$(git rev-parse "$remote_branch")
        if [ "$local_commit" != "$remote_commit" ]; then
            return 0  # Rebase is needed
        fi
    fi
    return 1  # No rebase needed
}

# Function to check if rebasing onto base branch is needed
needs_rebase_base() {
    local branch="$1"
    local base="$2"

    if ! git show-ref --verify --quiet "$base"; then
        log "Error: Base branch '$base' does not exist."
        exit 1
    fi

    local base_commit
    base_commit=$(git merge-base "$branch" "$base")
    local current_base_commit
    current_base_commit=$(git rev-parse "$base")
    if [ "$base_commit" != "$current_base_commit" ]; then
        return 0  # Rebase is needed
    fi
    return 1  # No rebase needed
}

# Determine if rebase onto remote counterpart is needed
rebase_remote_needed=false
if [ "$rebase_remote" = true ]; then
    if needs_rebase_remote "$current_branch"; then
        rebase_remote_needed=true
        log "Rebase onto remote counterpart is needed."
        # Show the commits that are different
        log "Differences between local '$current_branch' and remote 'origin/$current_branch':"
        git log --oneline "$current_branch".."origin/$current_branch"
    else
        log "No rebase onto remote counterpart is needed."
    fi
else
    log "Skipping rebase onto remote counterpart as per user request."
fi

# Determine if rebase onto base branch is needed
rebase_base_needed=false
if [ "$rebase_base" = true ]; then
    if needs_rebase_base "$current_branch" "$base_branch"; then
        rebase_base_needed=true
        log "Rebase onto base branch '$base_branch' is needed."
        # Show the commits that are different
        log "Differences between base '$base_branch' and your branch '$current_branch':"
        git log --oneline "$base_branch".."$current_branch"
    else
        log "No rebase onto base branch '$base_branch' is needed."
    fi
else
    log "Skipping rebase onto base branch as per user request."
fi

# If no rebasing is needed, exit the script
if [ "$rebase_remote_needed" = false ] && [ "$rebase_base_needed" = false ]; then
    log "Your branch is already up-to-date with the remote counterpart and the base branch."
    exit 0
fi

# Proceed with stashing and backup only if rebasing is needed
# Generate a UTC timestamp
timestamp=$(date -u +"%Y%m%d%H%M%S")

# Create a backup of the current branch with a timestamp suffix
backup_branch="${current_branch}_backup_${timestamp}"
log "Creating backup branch '$backup_branch'."
if ! git branch "$backup_branch"; then
    log "Error: Failed to create backup branch '$backup_branch'."
    exit 1
fi
actions_taken+=("Created backup branch '$backup_branch'.")

# Check for uncommitted changes and stash them if any
if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Uncommitted changes detected. Stashing changes..."
    if ! git stash push -u -m "Auto stash before safe rebase"; then
        log "Error: Failed to stash changes."
        exit 1
    fi
    actions_taken+=("Stashed uncommitted changes.")
fi

# Rebase onto the remote counterpart of the current branch if needed
if [ "$rebase_remote_needed" = true ]; then
    remote_branch="origin/$current_branch"
    log "Rebasing '$current_branch' onto its remote counterpart '$remote_branch'."
    if [ "$dry_run" = true ]; then
        if ! git rebase --dry-run "$remote_branch"; then
            log "Error: Dry run rebase onto '$remote_branch' failed."
            exit 1
        else
            log "Dry run rebase onto '$remote_branch' successful."
            actions_taken+=("Performed dry run rebase onto '$remote_branch'.")
        fi
    else
        if ! git rebase "$remote_branch"; then
            log "Error: Rebase onto '$remote_branch' failed."
            exit 1
        fi
        actions_taken+=("Rebased onto remote counterpart '$remote_branch'.")
    fi
fi

# Rebase onto the specified base branch if needed
if [ "$rebase_base_needed" = true ]; then
    log "Rebasing '$current_branch' onto base branch '$base_branch'."
    if [ "$dry_run" = true ]; then
        if ! git rebase --dry-run "$base_branch"; then
            log "Error: Dry run rebase onto '$base_branch' failed."
            exit 1
        else
            log "Dry run rebase onto '$base_branch' successful."
            actions_taken+=("Performed dry run rebase onto '$base_branch'.")
        fi
    else
        if ! git rebase "$base_branch"; then
            log "Error: Rebase onto '$base_branch' failed."
            exit 1
        fi
        actions_taken+=("Rebased onto base branch '$base_branch'.")
    fi
fi

# Restore stashed changes after rebasing
if git stash list | grep -q "Auto stash before safe rebase"; then
    log "Restoring stashed changes..."
    if ! git stash pop; then
        log "Error: Failed to apply stashed changes."
        exit 1
    fi
    actions_taken+=("Restored stashed changes.")
fi

log "Rebase of '$current_branch' completed successfully."
actions_taken+=("Completed rebase of '$current_branch'.")

# Suggest running tests or checks after rebasing
log "It's recommended to run your project's test suite to ensure everything works as expected."

# Optionally, push the current rebased branch to the remote repository
if [ "$rebase_remote_needed" = true ] || [ "$rebase_base_needed" = true ]; then
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
                actions_taken+=("Pushed rebased branch '$current_branch' to remote.")
                break
                ;;
            [Nn]* )
                log "Rebased branch not pushed to remote."
                actions_taken+=("Did not push rebased branch to remote.")
                break
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
fi

# Summary of actions taken
log "Summary of actions taken:"
for action in "${actions_taken[@]}"; do
    log "- $action"
done