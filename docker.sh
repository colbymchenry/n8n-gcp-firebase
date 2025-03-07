#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Stopping current n8n containers ===${NC}"
docker-compose down

echo -e "${BLUE}=== Building and starting n8n containers ===${NC}"
docker-compose up -d --build

echo -e "${GREEN}=== n8n is now running! ===${NC}"
echo -e "Access the n8n interface at ${BLUE}http://localhost:5678${NC}" 