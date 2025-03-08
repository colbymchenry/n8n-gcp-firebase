#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== n8n Cloud Run Deployment Tool ===${NC}"

# Run the check_requirements script
if [ -f "./check_requirements.sh" ]; then
    chmod +x ./check_requirements.sh
    ./check_requirements.sh
else
    echo -e "${RED}Error: check_requirements.sh script not found.${NC}"
    exit 1
fi

# Run the check_requirements script
if [ -f "./setup_project.sh" ]; then
    chmod +x ./setup_project.sh
    ./setup_project.sh
else
    echo -e "${RED}Error: setup_project.sh script not found.${NC}"
    exit 1
fi



