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

echo -e "\n${BLUE}=== Firebase Admin SDK Configuration ===${NC}"

# Look for Firebase Admin SDK JSON file
while true; do
  echo -e "${BLUE}Looking for Firebase Admin SDK credentials file...${NC}"
  FIREBASE_FILES=$(find . -name "*firebase-adminsdk*.json" 2>/dev/null)

  if [ -z "$FIREBASE_FILES" ]; then
    echo -e "${RED}No Firebase Admin SDK credentials file found.${NC}"
    echo -e "${YELLOW}Press Enter to retry search or 'c' to cancel: ${NC}"
    read RETRY_CHOICE
    
    if [ "$RETRY_CHOICE" == "c" ]; then
      echo -e "${YELLOW}Skipping Firebase Admin SDK configuration.${NC}"
      exit 0
    else
      echo -e "${BLUE}Please place your Firebase Admin SDK JSON file in the project directory and press Enter to continue...${NC}"
      read
      continue
    fi
  else
    # If multiple files found, let user select one
    if [ $(echo "$FIREBASE_FILES" | wc -l) -gt 1 ]; then
      echo -e "${YELLOW}Multiple Firebase Admin SDK files found:${NC}"
      i=1
      while read -r file; do
        echo "$i) $file"
        i=$((i+1))
      done <<< "$FIREBASE_FILES"
      
      read -p "Select a file (1-$((i-1))): " FILE_SELECTION
      FIREBASE_FILE_PATH=$(echo "$FIREBASE_FILES" | sed -n "${FILE_SELECTION}p")
    else
      FIREBASE_FILE_PATH=$FIREBASE_FILES
    fi
    break
  fi
done

echo -e "${GREEN}Using Firebase Admin SDK file: $FIREBASE_FILE_PATH${NC}"

# Read the Firebase Admin SDK JSON file and convert to a one-line JSON string
FIREBASE_CREDENTIALS=$(cat "$FIREBASE_FILE_PATH" | jq -c '.')

# Add Firebase credentials to setup.json
SETUP_JSON=$(echo $SETUP_JSON | jq --arg creds "$FIREBASE_CREDENTIALS" '. + {firebase_credentials: $creds}')

# Save updated setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

echo -e "${GREEN}Firebase Admin SDK credentials added to setup.json${NC}"
