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
    echo "  -b, --base-branch BRANCH   Specify the base branch to rebase onto (default is 'develop')."
    echo "  -d, --dry-run              Perform a dry run without making any changes."
    echo "  -h, --help                 Show this help message."
    echo
    exit 1
}

# Default values
dry_run=false
base_branch="develop"

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

# Build the list of upstream branches
build_upstream_list() {
    local branch="$1"
    local upstream_list=()
    local visited=()

    while true; do
        # Get the upstream (tracking) branch
        upstream=$(git rev-parse --abbrev-ref "$branch"@{upstream} 2>/dev/null || true)

        if [ -z "$upstream" ]; then
            # If no upstream, use the base branch specified
            if [ "$branch" != "$base_branch" ]; then
                upstream="$base_branch"
            else
                break
            fi
        fi

        # Remove remote prefix if present
        upstream="${upstream#origin/}"

        # Prevent infinite loops
        if [[ " ${visited[@]} " =~ " $upstream " ]]; then
            log "Warning: Detected a loop in branch hierarchy. Stopping traversal."
            break
        fi

        upstream_list+=("$upstream")
        visited+=("$upstream")
        branch="$upstream"

        if [ "$branch" == "$base_branch" ]; then
            break
        fi
    done

    # Reverse the list to have the base branch first
    echo "${upstream_list[@]}" | awk '{for(i=NF;i>0;i--)printf "%s ",$i;print""}'
}

# Get the list of upstream branches
log "Building list of upstream branches..."
upstream_branches=($(build_upstream_list "$current_branch"))
log "Upstream branches: ${upstream_branches[*]}"

# Update local references of upstream branches
for branch in "${upstream_branches[@]}"; do
    remote_branch="origin/$branch"
    if git show-ref --verify --quiet "refs/remotes/$remote_branch"; then
        log "Updating local reference of '$branch' from '$remote_branch'."
        if ! git fetch origin "$branch:$branch"; then
            log "Error: Failed to update local branch '$branch' from '$remote_branch'."
            exit 1
        fi
    else
        log "No remote counterpart for '$branch'. Skipping update."
    fi
done

# Perform the rebase of current branch onto the updated upstream chain
log "Rebasing current branch '$current_branch' onto updated upstream branches."
if ! git checkout "$current_branch"; then
    log "Error: Failed to checkout the current branch '$current_branch'."
    exit 1
fi

# Build the rebase command
rebase_onto="${upstream_branches[0]}"
for branch in "${upstream_branches[@]:1}"; do
    rebase_onto="$branch"
done

# Perform dry run if requested
if [ "$dry_run" = true ]; then
    log "Performing a dry run rebase of '$current_branch' onto '$rebase_onto'."
    if ! git rebase --dry-run "$rebase_onto"; then
        log "Error: Dry run rebase of '$current_branch' onto '$rebase_onto' failed."
        exit 1
    else
        log "Dry run rebase successful."
    fi
else
    log "Rebasing '$current_branch' onto '$rebase_onto'."
    if ! git rebase "$rebase_onto"; then
        log "Error: Rebase of '$current_branch' onto '$rebase_onto' failed."
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