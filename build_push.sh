#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get project name from command line argument
PROJECT_NAME=$1
UPDATE=$2

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

echo -e "\n${BLUE}=== Building and pushing Docker image ===${NC}"
    
# Extract GCP project from setup.json
GCP_PROJECT=$(echo "$SETUP_JSON" | grep -o '"gcp_project": *"[^"]*"' | cut -d'"' -f4)

# Image name in Google Container Registry
IMAGE_NAME="gcr.io/$GCP_PROJECT/n8n-$PROJECT_NAME:latest"

# Check if Dockerfile exists and create it if not
if [ ! -f "./$PROJECT_NAME/Dockerfile" ]; then
    echo -e "${YELLOW}No Dockerfile found. Creating one now.${NC}"
    create_dockerfile
fi

# Verify Dockerfile exists after potential creation
if [ ! -f "./$PROJECT_NAME/Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile still not found. Cannot continue with build.${NC}"
    exit 1
fi

# Check if we should build locally or use Cloud Build
read -p "Build image locally (l) or use Cloud Build (c)? (l/c): " build_choice

# Change to the project directory
cd "$PROJECT_NAME" || {
  echo -e "${RED}Error: Could not change to directory $PROJECT_NAME${NC}"
  exit 1
}


if [[ "$build_choice" == "l" ]]; then
    # Build locally
    echo "Building Docker image locally..."
    docker build -t $IMAGE_NAME
    
    # Push to GCR
    docker push $IMAGE_NAME
else
    # Use Cloud Build
    echo "Building and pushing image using Cloud Build..."
    
    # Use explicit Dockerfile path with Cloud Build
    gcloud builds submit --tag=$IMAGE_NAME --timeout=30m
    
    # Check if the build was successful
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Trying alternative build method with cloudbuild.yaml...${NC}"
        
        # Create a cloudbuild.yaml file for more explicit control
        cat > cloudbuild.yaml << EOL
steps:
- name: 'gcr.io/cloud-builders/docker'
args: ['build', '-t', '$IMAGE_NAME', '.']
- name: 'gcr.io/cloud-builders/docker'
args: ['push', '$IMAGE_NAME']
images: ['$IMAGE_NAME']
EOL
        
        echo "Using Cloud Build with config file..."
        gcloud builds submit --config=cloudbuild.yaml
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Build failed with both methods. Please check your Google Cloud setup and permissions.${NC}"
            exit 1
        fi
    fi
fi

echo -e "${GREEN}Image $IMAGE_NAME built and pushed to Google Container Registry${NC}"

# Change back to the parent directory
cd ..

# Run the deploy_cloud_run script
if [ -f "./deploy_cloud_run.sh" ]; then
    chmod +x ./deploy_cloud_run.sh
    ./deploy_cloud_run.sh "$PROJECT_NAME" "$UPDATE"
else
    echo -e "${RED}Error: deploy_cloud_run.sh script not found.${NC}"
    exit 1
fi