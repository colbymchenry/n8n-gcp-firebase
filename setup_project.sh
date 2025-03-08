#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize JSON structure
SETUP_JSON="{}"

# Get project name
while true; do
    read -p "Enter project name (lowercase letters, numbers, and hyphens only): " PROJECT_NAME
    # Validate project name for Google Cloud compatibility
    if [ -z "$PROJECT_NAME" ]; then
        echo -e "${RED}Project name cannot be empty. Please try again.${NC}"
    elif ! [[ $PROJECT_NAME =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo -e "${RED}Invalid project name. Project names must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number. Please try again.${NC}"
    else
        echo -e "${BLUE}Project name: ${GREEN}$PROJECT_NAME${NC}"
        # Add to JSON
        SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$PROJECT_NAME" '. + {project_name: $val}')
        break
    fi
done

# Create directory with project name
if [ -d "$PROJECT_NAME" ]; then
    read -p "Directory $PROJECT_NAME already exists. Overwrite? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ]; then
        echo "Setup cancelled. Exiting."
        exit 1
    fi
else
    mkdir -p "$PROJECT_NAME"
fi

# Get n8n credentials
read -p "Enter n8n username [admin]: " N8N_USER
N8N_USER=${N8N_USER:-admin}
echo -e "${BLUE}N8N username: ${GREEN}$N8N_USER${NC}"
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$N8N_USER" '. + {n8n_username: $val}')

while true; do
    read -p "Enter n8n password: " N8N_PASSWORD
    if [ -z "$N8N_PASSWORD" ]; then 
        echo -e "${RED}n8n password cannot be empty. Please try again.${NC}"
    else
        echo -e "${GREEN}Password set successfully.${NC}"
        # Add to JSON
        SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$N8N_PASSWORD" '. + {n8n_password: $val}')
        break
    fi
done

# Save setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

# Ask about Firebase Admin SDK
echo -e "\n${BLUE}=== Firebase Admin SDK Configuration ===${NC}"
echo -e "${YELLOW}Firebase Admin SDK allows n8n to interact with Firebase services like Firestore, Authentication, etc.${NC}"

read -p "Do you want to install Firebase Admin SDK? (y/n): " INSTALL_FIREBASE

if [ "$INSTALL_FIREBASE" == "y" ]; then
  echo -e "${GREEN}Firebase Admin SDK will be installed.${NC}"
  # Add to JSON
  SETUP_JSON=$(echo $SETUP_JSON | jq '. + {firebase_admin_sdk: true}')
else
  echo -e "${BLUE}Skipping Firebase Admin SDK installation.${NC}"
  # Add to JSON
  SETUP_JSON=$(echo $SETUP_JSON | jq '. + {firebase_admin_sdk: false}')
fi

# Save updated setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

if [ "$INSTALL_FIREBASE" == "y" ]; then
    # Run the setup_firebase script
    if [ -f "./setup_firebase.sh" ]; then
        chmod +x ./setup_firebase.sh
        ./setup_firebase.sh "$PROJECT_NAME"
    else
        echo -e "${RED}Error: setup_firebase.sh script not found.${NC}"
        exit 1
    fi
fi

# Run the setup_postgres script
if [ -f "./setup_postgres.sh" ]; then
    chmod +x ./setup_postgres.sh
    ./setup_postgres.sh "$PROJECT_NAME"
else
    echo -e "${RED}Error: setup_postgres.sh script not found.${NC}"
    exit 1
fi