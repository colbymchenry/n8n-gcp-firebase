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

# Extract values from setup.json
N8N_USERNAME=$(echo "$SETUP_JSON" | grep -o '"n8n_username": "[^"]*' | cut -d'"' -f4)
N8N_PASSWORD=$(echo "$SETUP_JSON" | grep -o '"n8n_password": "[^"]*' | cut -d'"' -f4)
DB_HOST=$(echo "$SETUP_JSON" | grep -o '"neon_db_host": "[^"]*' | cut -d'"' -f4)
DB_PASSWORD=$(echo "$SETUP_JSON" | grep -o '"neon_db_password": "[^"]*' | cut -d'"' -f4)
DB_NAME=$(echo "$SETUP_JSON" | grep -o '"neon_db_name": "[^"]*' | cut -d'"' -f4)
DB_USER=$(echo "$SETUP_JSON" | grep -o '"neon_db_user": "[^"]*' | cut -d'"' -f4)
DB_SCHEMA=$(echo "$SETUP_JSON" | grep -o '"neon_db_schema": "[^"]*' | cut -d'"' -f4)
INSTALL_FIREBASE=$(echo "$SETUP_JSON" | grep -o '"firebase_admin_sdk": [^,}]*' | cut -d':' -f2 | tr -d ' "')
FIREBASE_CREDENTIALS=$(echo "$SETUP_JSON" | jq -c '.firebase_credentials')

echo -e "\n${BLUE}=== Setting up Docker ===${NC}"

# Create docker-compose.yml based on whether Firebase is included
    cat > "$PROJECT_NAME/docker-compose.yml" << EOL
services:
  n8n:
    image: custom-n8n
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - NODE_FUNCTION_ALLOW_EXTERNAL=*
      - GENERIC_TIMEZONE=UTC
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USERNAME}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_PORT=8080
      - N8N_LISTEN_ADDRESS=0.0.0.0
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      
      # PostgreSQL configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=${DB_NAME}
      - DB_POSTGRESDB_HOST=${DB_HOST}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=${DB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - DB_POSTGRESDB_SCHEMA=${DB_SCHEMA:-public}
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
      $(if [ "$INSTALL_FIREBASE" = "true" ]; then echo "- FIREBASE_CREDENTIALS=${FIREBASE_CREDENTIALS}"; fi)
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOL

echo -e "\n${GREEN}docker-compose.yml file created.${NC}"


# Create simple Dockerfile for n8n
cat > "$PROJECT_NAME/Dockerfile" << EOL
# Use n8n Docker image
FROM n8nio/n8n:latest

# Switch to root user for configuration
USER root

# Install Firebase Admin SDK if requested
$(if [ "$INSTALL_FIREBASE" = "true" ]; then echo "RUN cd /usr/local/lib/node_modules/n8n && npm install firebase-admin"; fi)
$(if [ "$INSTALL_FIREBASE" = "true" ]; then echo "ENV FIREBASE_CREDENTIALS=${FIREBASE_CREDENTIALS}"; fi)

# Set to allow all external Node modules by default
ENV NODE_FUNCTION_ALLOW_EXTERNAL=*

# Set environment variables for Cloud Run
ENV N8N_PORT=8080
ENV N8N_LISTEN_ADDRESS=0.0.0.0
ENV N8N_PROTOCOL=https
ENV NODE_ENV=production

# Expose port 8080 for Cloud Run
EXPOSE 8080

# The default n8n user
USER node

EOL

echo -e "${GREEN}Dockerfile created.${NC}"

echo -e "\n${YELLOW}To start the n8n server, run:${NC}"
echo -e "docker-compose up -d"

# Run the build_push script
if [ -f "./build_push.sh" ]; then
    chmod +x ./build_push.sh
    ./build_push.sh "$PROJECT_NAME"
else
    echo -e "${RED}Error: build_push.sh script not found.${NC}"
    exit 1
fi