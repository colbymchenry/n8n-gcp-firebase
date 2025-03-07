#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_NAME=""
PROJECT_DIR=""
GCP_PROJECT=""
GCP_REGION="us-central1"
SERVICE_NAME="n8n-serverless"
# Resources for Cloud Run - Look up optimal values
MAX_INSTANCES=5
MIN_INSTANCES=0
MEMORY="1Gi"
CPU=1
TIMEOUT="900s"
CONCURRENCY=80
DOMAIN_NAME=""
INCLUDE_FIREBASE=""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}=== Checking prerequisites ===${NC}"
    
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
    
    if [ ! -f "./setup.sh" ]; then
        echo -e "${RED}Error: setup.sh script not found in current directory.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}All required tools are installed.${NC}"
}

# Run setup script or use existing project
setup_project() {
    echo -e "${BLUE}=== Setting up project ===${NC}"
    
    read -p "Create a new project with setup.sh (n) or use existing directory (e)? (n/e): " setup_choice
    
    if [[ "$setup_choice" == "n" ]]; then
        # Run the setup script to create a new project
        read -p "Enter project name for n8n setup: " PROJECT_NAME
        if [ -z "$PROJECT_NAME" ]; then
            echo -e "${RED}Error: Project name cannot be empty.${NC}"
            exit 1
        fi
        
        # Run setup.sh to create the project files
        ./setup.sh
        
        # Check if project directory was created
        if [ ! -d "./$PROJECT_NAME" ]; then
            echo -e "${RED}Error: Project directory '$PROJECT_NAME' was not created by setup.sh.${NC}"
            exit 1
        fi
        
        # Set the project directory
        PROJECT_DIR="./$PROJECT_NAME"
        
        # Determine if user chose to include Firebase (for later use in Dockerfile)
        # Parse the .env file to check for Firebase config
        if [ -f "$PROJECT_DIR/.env" ]; then
            grep -q "FIREBASE_PROJECT_ID" "$PROJECT_DIR/.env"
            if [ $? -eq 0 ]; then
                INCLUDE_FIREBASE="y"
            else
                INCLUDE_FIREBASE="n"
            fi
        fi
    else
        # Use an existing directory
        read -p "Enter the path to your existing n8n project directory: " PROJECT_DIR
        if [ ! -d "$PROJECT_DIR" ]; then
            echo -e "${RED}Error: Directory '$PROJECT_DIR' does not exist.${NC}"
            exit 1
        fi
        
        # Check for required files
        if [ ! -f "$PROJECT_DIR/docker-compose.yml" ] || [ ! -f "$PROJECT_DIR/Dockerfile" ] || [ ! -f "$PROJECT_DIR/.env" ]; then
            echo -e "${RED}Error: Required files (docker-compose.yml, Dockerfile, .env) not found in $PROJECT_DIR.${NC}"
            exit 1
        fi
        
        # Extract project name from directory
        PROJECT_NAME=$(basename "$PROJECT_DIR")
        
        # Determine if user is using Firebase
        if [ -f "$PROJECT_DIR/.env" ]; then
            grep -q "FIREBASE_PROJECT_ID" "$PROJECT_DIR/.env"
            if [ $? -eq 0 ]; then
                INCLUDE_FIREBASE="y"
            else
                INCLUDE_FIREBASE="n"
            fi
        fi
        
        # Check existing Dockerfile for Firebase
        if [ -f "$PROJECT_DIR/Dockerfile" ]; then
            grep -q "firebase-admin" "$PROJECT_DIR/Dockerfile"
            if [ $? -eq 0 ]; then
                INCLUDE_FIREBASE="y"
            fi
        fi
    fi
    
    echo -e "${GREEN}Using project: $PROJECT_NAME in directory: $PROJECT_DIR${NC}"
    
    # Change to project directory
    cd "$PROJECT_DIR"
}

# Initialize GCP configuration
initialize_gcp() {
    echo -e "${BLUE}=== Initializing GCP configuration ===${NC}"
    
    # Get GCP project
    current_project=$(gcloud config get-value project 2>/dev/null)
    read -p "Enter GCP project ID [$current_project]: " input_project
    GCP_PROJECT=${input_project:-$current_project}
    
    if [ -z "$GCP_PROJECT" ]; then
        echo -e "${RED}Error: No project specified.${NC}"
        exit 1
    fi
    
    # Set the project in gcloud config
    echo "Setting project to: $GCP_PROJECT"
    gcloud config set project "$GCP_PROJECT"

    # Choose region
    read -p "Enter GCP region [$GCP_REGION]: " input_region
    GCP_REGION=${input_region:-$GCP_REGION}
    
    # Set service name
    read -p "Enter Cloud Run service name [$SERVICE_NAME]: " input_service
    SERVICE_NAME=${input_service:-$SERVICE_NAME}
    
    # Configure resources
    read -p "Enter max instances [$MAX_INSTANCES]: " input_max
    MAX_INSTANCES=${input_max:-$MAX_INSTANCES}
    
    read -p "Enter min instances [$MIN_INSTANCES]: " input_min
    MIN_INSTANCES=${input_min:-$MIN_INSTANCES}
    
    read -p "Enter memory (e.g., 512Mi, 1Gi) [$MEMORY]: " input_memory
    MEMORY=${input_memory:-$MEMORY}
    
    read -p "Enter CPU count [$CPU]: " input_cpu
    CPU=${input_cpu:-$CPU}
    
    # Get domain name (optional)
    read -p "Enter your custom domain name for n8n (optional): " input_domain
    DOMAIN_NAME=${input_domain:-$DOMAIN_NAME}
}

# Enable required GCP APIs
enable_apis() {
    echo -e "${BLUE}=== Enabling required GCP APIs ===${NC}"
    
    echo "Enabling Cloud Run API..."
    gcloud services enable run.googleapis.com
    
    echo "Enabling Container Registry API..."
    gcloud services enable containerregistry.googleapis.com
    
    echo "Enabling Cloud Build API..."
    gcloud services enable cloudbuild.googleapis.com
    
    echo "Enabling Secret Manager API..."
    gcloud services enable secretmanager.googleapis.com
}

# Set Cloud Run environment variables
configure_env_vars() {
    echo -e "${BLUE}=== Configuring environment variables ===${NC}"
    
    # Load environment variables from .env file
    set -a
    source .env
    set +a
    
    # Create a temporary env file for Cloud Run
    ENV_FILE="cloud-run-env.yaml"
    
    echo "# Cloud Run environment variables for n8n" > $ENV_FILE
    
    # Core n8n settings for Cloud Run
    echo "N8N_PORT: \"8080\"" >> $ENV_FILE
    echo "N8N_LISTEN_ADDRESS: \"0.0.0.0\"" >> $ENV_FILE
    echo "N8N_EDITOR_BASE_URL: \"\"" >> $ENV_FILE
    echo "NODE_OPTIONS: \"--max-old-space-size=4096\"" >> $ENV_FILE
    
    # Performance settings
    echo "N8N_METRICS: \"false\"" >> $ENV_FILE
    echo "N8N_DIAGNOSTICS_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_HIRING_BANNER_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_VERSION_NOTIFICATIONS_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_PERSONALIZATION_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_ONBOARDING_FLOW_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_TEMPLATES_ENABLED: \"false\"" >> $ENV_FILE
    echo "N8N_DISABLE_PRODUCTION_MAIN_PROCESS: \"false\"" >> $ENV_FILE
    echo "N8N_DISABLE_WEBHOOK_ONBOARDING: \"true\"" >> $ENV_FILE
    echo "N8N_LOG_LEVEL: \"verbose\"" >> $ENV_FILE
    
    # Authentication
    echo "N8N_BASIC_AUTH_ACTIVE: \"true\"" >> $ENV_FILE
    echo "N8N_BASIC_AUTH_USER: \"$N8N_BASIC_AUTH_USER\"" >> $ENV_FILE
    echo "N8N_BASIC_AUTH_PASSWORD: \"$N8N_BASIC_AUTH_PASSWORD\"" >> $ENV_FILE
    
    # Cloud Run URL generation
    if [ -z "$DOMAIN_NAME" ]; then
        SERVICE_URL="https://$SERVICE_NAME-$(echo $RANDOM | md5sum | head -c 6)-$GCP_REGION.a.run.app"
    else
        SERVICE_URL="https://$DOMAIN_NAME"
    fi
    echo "N8N_HOST: \"${SERVICE_URL#https://}\"" >> $ENV_FILE
    echo "N8N_PROTOCOL: \"https\"" >> $ENV_FILE
    echo "WEBHOOK_URL: \"$SERVICE_URL/\"" >> $ENV_FILE
    
    # Database configuration
    echo "DB_TYPE: \"postgresdb\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_HOST: \"$DB_POSTGRESDB_HOST\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_PORT: \"$DB_POSTGRESDB_PORT\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_DATABASE: \"$DB_POSTGRESDB_DATABASE\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_USER: \"$DB_POSTGRESDB_USER\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_PASSWORD: \"$DB_POSTGRESDB_PASSWORD\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_SCHEMA: \"$DB_POSTGRESDB_SCHEMA\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: \"false\"" >> $ENV_FILE
    
    # Serverless-specific configuration
    echo "N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN: \"true\"" >> $ENV_FILE
    
    # Generate encryption key if not provided
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
        echo -e "${YELLOW}Generated encryption key: $N8N_ENCRYPTION_KEY${NC}"
        echo -e "${YELLOW}IMPORTANT: Save this key! You will need it if you redeploy n8n.${NC}"
    fi
    echo "N8N_ENCRYPTION_KEY: \"$N8N_ENCRYPTION_KEY\"" >> $ENV_FILE
    
    # Timezone
    echo "GENERIC_TIMEZONE: \"UTC\"" >> $ENV_FILE
    
    # Optional settings
    if [ ! -z "$NODE_FUNCTION_ALLOW_EXTERNAL" ]; then
        echo "NODE_FUNCTION_ALLOW_EXTERNAL: \"$NODE_FUNCTION_ALLOW_EXTERNAL\"" >> $ENV_FILE
    fi
    
    # Add Firebase variables if present
    if [ ! -z "$FIREBASE_PROJECT_ID" ]; then
        echo "FIREBASE_PROJECT_ID: \"$FIREBASE_PROJECT_ID\"" >> $ENV_FILE
        echo "FIREBASE_PRIVATE_KEY_ID: \"$FIREBASE_PRIVATE_KEY_ID\"" >> $ENV_FILE
        echo "FIREBASE_PRIVATE_KEY: \"$FIREBASE_PRIVATE_KEY\"" >> $ENV_FILE
        echo "FIREBASE_CLIENT_EMAIL: \"$FIREBASE_CLIENT_EMAIL\"" >> $ENV_FILE
        echo "FIREBASE_CLIENT_ID: \"$FIREBASE_CLIENT_ID\"" >> $ENV_FILE
        echo "FIREBASE_CLIENT_X509_CERT_URL: \"$FIREBASE_CLIENT_X509_CERT_URL\"" >> $ENV_FILE
        echo "NODE_FUNCTION_ALLOW_EXTERNAL: \"firebase-admin\"" >> $ENV_FILE
    fi
    
    echo -e "${GREEN}Environment variables configured in $ENV_FILE${NC}"
}

# Function to create Dockerfile based on Firebase preference
create_dockerfile() {
    echo -e "${BLUE}=== Creating Dockerfile ===${NC}"
    
    # Check if Dockerfile already exists
    if [ -f "./Dockerfile" ]; then
        echo "Dockerfile already exists at: $(pwd)/Dockerfile"
        read -p "Do you want to overwrite it? (y/n): " overwrite_dockerfile
        if [[ "$overwrite_dockerfile" != "y" ]]; then
            echo "Using existing Dockerfile."
            return
        fi
    fi
    
    # Use Firebase preference from earlier setup
    # If INCLUDE_FIREBASE is empty (older project), ask the user
    if [ -z "$INCLUDE_FIREBASE" ]; then
        echo "No Firebase preference detected from setup."
        read -p "Include Firebase Admin in the Dockerfile? (y/n): " include_firebase
        INCLUDE_FIREBASE=$(echo "$include_firebase" | tr '[:upper:]' '[:lower:]')
    else
        echo -e "${BLUE}Using Firebase preference from setup: $INCLUDE_FIREBASE${NC}"
    fi
    
    # Create simple Dockerfile for n8n
    cat > Dockerfile << EOL
# Use n8n Docker image
FROM n8nio/n8n:latest

# Switch to root user for configuration
USER root

# Set environment variables for Cloud Run
ENV N8N_PORT=8080
ENV N8N_LISTEN_ADDRESS=0.0.0.0
ENV N8N_PROTOCOL=https
ENV NODE_ENV=production

# Expose port 8080 for Cloud Run
EXPOSE 8080
EOL
    
    # Add Firebase Admin if requested
    if [[ "$INCLUDE_FIREBASE" = "y" ]]; then
        cat >> Dockerfile << EOL
# Install firebase-admin
# Install firebase-admin in the n8n modules directory
WORKDIR /usr/local/lib/node_modules/n8n
RUN npm install firebase-admin

EOL
        
        # Update environment file to include Firebase settings
        echo "NODE_FUNCTION_ALLOW_EXTERNAL: \"firebase-admin\"" >> $ENV_FILE
    fi
    
    # Finalize Dockerfile
    cat >> Dockerfile << EOL
# Switch back to node user for runtime
USER node

EOL
    
    echo -e "${GREEN}Dockerfile created successfully.${NC}"
}

# Build and push Docker image to GCR
build_and_push_image() {
    echo -e "${BLUE}=== Building and pushing Docker image ===${NC}"
    
    # Image name in Google Container Registry
    IMAGE_NAME="gcr.io/$GCP_PROJECT/n8n-$PROJECT_NAME:latest"
    
    # Check if Dockerfile exists and create it if not
    if [ ! -f "./Dockerfile" ]; then
        echo -e "${YELLOW}No Dockerfile found. Creating one now.${NC}"
        create_dockerfile
    fi
    
    # Verify Dockerfile exists after potential creation
    if [ ! -f "./Dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile still not found. Cannot continue with build.${NC}"
        exit 1
    fi
    
    # Show Dockerfile contents for debugging
    echo -e "${BLUE}Using this Dockerfile:${NC}"
    cat ./Dockerfile
    echo
    
    # Check if we should build locally or use Cloud Build
    read -p "Build image locally (l) or use Cloud Build (c)? (l/c): " build_choice
    
    if [[ "$build_choice" == "l" ]]; then
        # Build locally
        echo "Building Docker image locally..."
        docker build -t $IMAGE_NAME .
        
        # Push to GCR
        echo "Pushing image to Google Container Registry..."
        docker push $IMAGE_NAME
    else
        # Use Cloud Build
        echo "Building and pushing image using Cloud Build..."
        
        # Use explicit Dockerfile path with Cloud Build
        echo "Running: gcloud builds submit --tag=$IMAGE_NAME --timeout=30m ."
        gcloud builds submit --tag=$IMAGE_NAME --timeout=30m .
        
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
}

# Deploy to Cloud Run
deploy_to_cloud_run() {
    echo -e "${BLUE}=== Deploying to Cloud Run ===${NC}"
    
    # Image name in Google Container Registry
    IMAGE_NAME="gcr.io/$GCP_PROJECT/n8n-$PROJECT_NAME:latest"
    
    echo "Deploying service $SERVICE_NAME to Cloud Run..."
    gcloud run deploy $SERVICE_NAME \
        --image=$IMAGE_NAME \
        --platform=managed \
        --region=$GCP_REGION \
        --allow-unauthenticated \
        --memory=$MEMORY \
        --cpu=$CPU \
        --port=8080 \
        --timeout=$TIMEOUT \
        --max-instances=$MAX_INSTANCES \
        --min-instances=$MIN_INSTANCES \
        --concurrency=$CONCURRENCY \
        --env-vars-file=$ENV_FILE \
        --cpu-boost \
        --execution-environment=gen1 \
        --no-cpu-throttling
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform=managed --region=$GCP_REGION --format='value(status.url)')
    
    # Check if deployment was successful
    if [ $? -eq 0 ] && [ ! -z "$SERVICE_URL" ]; then
        echo -e "${GREEN}=== Deployment complete! ===${NC}"
        echo -e "Your n8n instance is available at: ${BLUE}$SERVICE_URL${NC}"
        echo -e "Username: ${BLUE}$N8N_BASIC_AUTH_USER${NC}"
        echo -e "Password: ${BLUE}$N8N_BASIC_AUTH_PASSWORD${NC}"
        
        if [ ! -z "$DOMAIN_NAME" ]; then
            echo -e "${YELLOW}Next Steps for Custom Domain:${NC}"
            echo -e "1. Map your domain to Cloud Run: ${BLUE}gcloud beta run domain-mappings create --service=$SERVICE_NAME --domain=$DOMAIN_NAME --region=$GCP_REGION${NC}"
            echo -e "2. Configure DNS records according to Cloud Run instructions"
        fi
        
        echo -e "${YELLOW}IMPORTANT NOTE:${NC}"
        echo -e "For serverless n8n, your encryption key is: ${BLUE}$N8N_ENCRYPTION_KEY${NC}"
        echo -e "Save this key in a secure location. You will need it if you redeploy n8n to decrypt existing credentials."
    else
        echo -e "${RED}=== Deployment failed! ===${NC}"
        echo -e "To view logs and troubleshoot the error, run:"
        echo -e "${BLUE}gcloud run services logs read $SERVICE_NAME --region=$GCP_REGION${NC}"
        
        # Try to get more detailed information
        echo -e "${YELLOW}Getting detailed deployment information...${NC}"
        gcloud run revisions list --service=$SERVICE_NAME --region=$GCP_REGION --format="table(name, active, status.conditions.status.list():label=Status, status.conditions.message.list():label=Message)"
    fi
}

# Clean up temporary files
cleanup() {
    echo -e "${BLUE}=== Cleaning up ===${NC}"
    
    if [ -f "$ENV_FILE" ]; then
        read -p "Delete temporary environment file $ENV_FILE? (y/n): " delete_env
        if [[ "$delete_env" == "y" ]]; then
            rm $ENV_FILE
            echo "Removed $ENV_FILE"
        else
            echo "Keeping $ENV_FILE for future reference"
        fi
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== n8n Cloud Run Deployment Tool ===${NC}"
    
    check_prerequisites
    setup_project
    initialize_gcp
    enable_apis
    configure_env_vars
    create_dockerfile
    build_and_push_image
    deploy_to_cloud_run
    cleanup
    
    echo -e "${GREEN}=== Deployment Complete! ===${NC}"
}

# Run main function
main 