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

# Neon database info with menu options
echo -e "\n${BLUE}=== Neon PostgreSQL Configuration ===${NC}"
echo -e "${YELLOW}Neon is a serverless PostgreSQL service that works well with n8n on a Google Cloud Run instance.${NC}"

# DB Host
while true; do
    read -p "Enter Neon DB host (e.g., ep-example-123456.us-east-2.aws.neon.tech): " NEON_DB_HOST
    if [ -z "$NEON_DB_HOST" ]; then
        echo -e "${RED}Neon DB host cannot be empty. Please try again.${NC}"
    else
        echo -e "${BLUE}Neon DB host: ${GREEN}$NEON_DB_HOST${NC}"
        # Add to JSON
        SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$NEON_DB_HOST" '. + {neon_db_host: $val}')
        break
    fi
done

# DB Password
while true; do
    read -p "Enter Neon DB password: " NEON_DB_PASSWORD
    echo ""
    if [ -z "$NEON_DB_PASSWORD" ]; then
        echo -e "${RED}Neon DB password cannot be empty. Please try again.${NC}"
    else
        echo -e "${GREEN}Password set successfully.${NC}"
        # Add to JSON
        SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$NEON_DB_PASSWORD" '. + {neon_db_password: $val}')
        break
    fi
done

# DB Name with options
echo -e "\n${YELLOW}Database Name Options:${NC}"
echo -e "This is the name of your PostgreSQL database in Neon."
echo -e "1) neondb (Default database name)"
echo -e "2) n8n (Specific to n8n application)"
echo -e "3) Custom database name"

read -p "Select database name [1-3, default: 1]: " db_name_choice
case $db_name_choice in
    2) NEON_DB_NAME="n8n" ;;
    3) read -p "Enter custom database name: " NEON_DB_NAME ;;
    *) NEON_DB_NAME="neondb" ;;
esac
echo -e "${BLUE}Using database name: ${GREEN}$NEON_DB_NAME${NC}"
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$NEON_DB_NAME" '. + {neon_db_name: $val}')

# DB User with options
echo -e "\n${YELLOW}Database User Options:${NC}"
echo -e "This is the username for connecting to your PostgreSQL database."
echo -e "1) neondb_owner (Default Neon database owner)"
echo -e "2) n8n_user (Specific to n8n application)"
echo -e "3) Custom database user"

read -p "Select database user [1-3, default: 1]: " db_user_choice
case $db_user_choice in
    2) NEON_DB_USER="n8n_user" ;;
    3) read -p "Enter custom database user: " NEON_DB_USER ;;
    *) NEON_DB_USER="neondb_owner" ;;
esac
echo -e "${BLUE}Using database user: ${GREEN}$NEON_DB_USER${NC}"
# Add to JSON   
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$NEON_DB_USER" '. + {neon_db_user: $val}')

# DB Schema with options
echo -e "\n${YELLOW}Database Schema Options:${NC}"
echo -e "Schema separates database objects into logical groups. Most applications use the default 'public' schema."
echo -e "1) public (Default schema)"
echo -e "2) n8n (Dedicated schema for n8n)"
echo -e "3) Custom schema name"

read -p "Select database schema [1-3, default: 1]: " db_schema_choice
case $db_schema_choice in
    2) NEON_DB_SCHEMA="n8n" ;;
    3) read -p "Enter custom schema name: " NEON_DB_SCHEMA ;;
    *) NEON_DB_SCHEMA="public" ;;
esac
echo -e "${BLUE}Using database schema: ${GREEN}$NEON_DB_SCHEMA${NC}"
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$NEON_DB_SCHEMA" '. + {neon_db_schema: $val}')

# Save setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

# Run the setup_postgres script
if [ -f "./setup_gcp.sh" ]; then
    chmod +x ./setup_gcp.sh
    ./setup_gcp.sh "$PROJECT_NAME"
else
    echo -e "${RED}Error: setup_gcp.sh script not found.${NC}"
    exit 1
fi