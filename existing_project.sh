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

# Continue looping until user chooses to exit
while true; do
    # Display update options menu
    echo -e "\n${BLUE}=== Existing Project Update ===${NC}"
    echo -e "${YELLOW}Please select an option to update:${NC}"
    echo "1) Update Firebase credentials"
    echo "2) Update PostgreSQL settings"
    echo "3) Update NPM packages"
    echo "4) Rebuild & Deploy"
    echo "5) Exit"

    # Get user choice
    read -p "Enter your choice (1-5): " UPDATE_CHOICE

    case $UPDATE_CHOICE in
        1)
            echo -e "${GREEN}Updating Firebase credentials...${NC}"
            if [ -f "./setup_firebase.sh" ]; then
                chmod +x ./setup_firebase.sh
                ./setup_firebase.sh "$PROJECT_NAME"
            else
                echo -e "${RED}Error: setup_firebase.sh script not found.${NC}"
            fi
            ;;
        2)
            echo -e "${GREEN}Updating PostgreSQL settings...${NC}"
            if [ -f "./setup_postgres.sh" ]; then
                chmod +x ./setup_postgres.sh
                ./setup_postgres.sh "$PROJECT_NAME" true
            else
                echo -e "${RED}Error: setup_postgres.sh script not found.${NC}"
            fi
            ;;
        3)
            echo -e "${GREEN}Updating NPM packages...${NC}"
            if [ -f "./setup_npm_packages.sh" ]; then
                chmod +x ./setup_npm_packages.sh
                ./setup_npm_packages.sh "$PROJECT_NAME"
            else
                echo -e "${RED}Error: setup_npm_packages.sh script not found.${NC}"
            fi
            ;;
        4)
            echo -e "${GREEN}Rebuilding and deploying...${NC}"
            if [ -f "./setup_docker.sh" ]; then
                chmod +x ./setup_docker.sh
                ./setup_docker.sh "$PROJECT_NAME" true
            else
                echo -e "${RED}Error: setup_docker.sh script not found.${NC}"
            fi
            ;;
        5)
            echo -e "${BLUE}Exiting without further updates.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac
done
