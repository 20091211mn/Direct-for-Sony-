#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Colors for terminal styling
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RED='\033[1;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Git Automation Script Started ===${NC}"

# 1. Show current git status
echo -e "${GREEN}Checking git status...${NC}"
git status

# 2. Add all modified and new files
echo -e "${GREEN}Adding all changes to staging...${NC}"
git add .

# 3. Ask user for a custom commit message
echo -e "${BLUE}Enter your commit message (or press Enter for default):${NC}"
read commit_msg

# Set a default message if input is empty
if [ -z "$commit_msg" ]; then
    commit_msg="Update project files via Termux script"
fi

# 4. Commit changes
echo -e "${GREEN}Committing changes with message: '$commit_msg'...${NC}"
git commit -m "$commit_msg"

# 5. Push to GitHub repository
echo -e "${GREEN}Pushing changes to remote repository (main branch)...${NC}"
git push origin main

echo -e "${BLUE}=== Process Completed Successfully! ===${NC}"

