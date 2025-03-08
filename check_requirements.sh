#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if ! command_exists gcloud; then
    echo -e "${RED}Error: gcloud CLI not found. Please install it first.${NC}"
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command_exists docker; then
    echo -e "${RED}Error: docker not found. Please install it first.${NC}"
    echo "Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

echo -e "${GREEN}Docker ${BLUE}and ${GREEN}gcloud ${BLUE}are installed.${NC}"

echo -e "${BLUE}=== Enabling required GCP APIs ===${NC}"
    
echo -e "${GREEN}Enabling Cloud Run API...${NC}"
gcloud services enable run.googleapis.com

echo -e "${GREEN}Enabling Container Registry API...${NC}"
gcloud services enable containerregistry.googleapis.com

echo -e "${GREEN}Enabling Cloud Build API...${NC}"
gcloud services enable cloudbuild.googleapis.com

echo -e "${GREEN}Enabling Secret Manager API...${NC}"
gcloud services enable secretmanager.googleapis.com