#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# List of branches to keep
KEEP_BRANCHES=("main" "master" "development" "acceptance" "production")

# Function to check if a branch should be kept
should_keep_branch() {
    local branch=$1
    for keep in "${KEEP_BRANCHES[@]}"; do
        if [[ "$branch" == "$keep" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to clean branches in a repository
clean_repo() {
    local repo_dir=$1
    
    # Convert to absolute path
    repo_dir=$(realpath "$repo_dir")
    
    echo -e "${GREEN}Processing repository: ${repo_dir}${NC}"
    
    # Check if directory exists and is a git repository
    if [ ! -d "$repo_dir" ]; then
        echo -e "${RED}Error: Directory does not exist: ${repo_dir}${NC}"
        return 1
    fi
    
    if [ ! -d "$repo_dir/.git" ]; then
        echo -e "${RED}Error: Not a git repository: ${repo_dir}${NC}"
        return 1
    fi
    
    # Change to repository directory
    if ! cd "$repo_dir"; then
        echo -e "${RED}Error: Could not change to directory: ${repo_dir}${NC}"
        return 1
    fi

    # Fetch all branches
    echo "Fetching all branches..."
    if ! git fetch --all; then
        echo -e "${RED}Error: Failed to fetch branches${NC}"
        return 1
    fi

    # Get list of all local branches
    local_branches=$(git branch | sed 's/^[* ] //')
    
    # Get list of merged branches
    merged_branches=$(git branch --merged | sed 's/^[* ] //')
    
    # Process each local branch
    for branch in $local_branches; do
        # Skip if branch should be kept
        if should_keep_branch "$branch"; then
            echo -e "${YELLOW}Keeping protected branch: $branch${NC}"
            continue
        fi
        
        # Check if branch is merged
        if echo "$merged_branches" | grep -q "^$branch$"; then
            echo "Removing merged branch: $branch"
            git branch -d "$branch"
        else
            echo -e "${YELLOW}Warning: Branch '$branch' is not merged. Use -D to force delete${NC}"
        fi
    done
    
    echo "Repository cleanup complete"
    echo "----------------------------------------"
    
}

# Main script
echo "Starting Git repository cleanup..."

# Get the current directory's absolute path
START_DIR=$(pwd)

# Find all Git repositories in the current directory and subdirectories
while IFS= read -r -d '' gitdir; do
    repo_path=$(dirname "$gitdir")
    clean_repo "$repo_path"
    # Return to starting directory after processing each repo
    cd "$START_DIR" || exit 1
done < <(find "$(pwd)" -type d -name ".git" -print0)

echo -e "${GREEN}All repositories processed!${NC}"