#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get project name from command line argument
PROJECT_NAME=$1

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Project name not provided. Please run setup_project.sh first.${NC}"
    exit 1
fi

# Load existing JSON from setup.json
if [ -f "$PROJECT_NAME/setup.json" ]; then
    SETUP_JSON=$(cat "$PROJECT_NAME/setup.json")
else
    # If no setup.json exists, exit with error
    echo -e "${RED}Error: No setup.json file found. Please run setup_project.sh first.${NC}"
    exit 1
fi

echo -e "\n${BLUE}=== External Packages Configuration ===${NC}"

# Ask user for packages
echo -e "${BLUE}Please enter the npm packages you want to install, separated by commas:${NC}"
echo -e "${YELLOW}Example: react,react-dom,@remix-run/react${NC}"
read PACKAGES_INPUT

if [ -z "$PACKAGES_INPUT" ]; then
    echo -e "${YELLOW}No packages specified. Skipping external packages configuration.${NC}"
    exit 0
fi

# Convert comma-separated list to JSON array
PACKAGES_JSON=$(echo $PACKAGES_INPUT | tr ',' '\n' | jq -R . | jq -s .)

# Add packages to setup.json
SETUP_JSON=$(echo $SETUP_JSON | jq --argjson pkgs "$PACKAGES_JSON" '. + {external_packages: $pkgs}')

# Save updated setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

echo -e "${GREEN}External packages added to setup.json${NC}"
