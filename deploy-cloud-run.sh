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
        
        # Run setup.sh with the project name as an argument
        ./setup.sh "$PROJECT_NAME"
        
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
        if [ ! -f "$PROJECT_DIR/docker-compose.yml" ] || [ ! -f "$PROJECT_DIR/.env" ]; then
            echo -e "${RED}Error: Required files (docker-compose.yml, .env) not found in $PROJECT_DIR.${NC}"
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
        
        # If Firebase isn't enabled but there's a Firebase JSON file, ask if user wants to enable it
        if [ "$INCLUDE_FIREBASE" != "y" ]; then
            # Check for Firebase JSON files in the project directory
            FIREBASE_JSON_FILES=$(find "$PROJECT_DIR" -name "*firebase-adminsdk*.json" -type f 2>/dev/null)
            
            if [ ! -z "$FIREBASE_JSON_FILES" ]; then
                echo -e "\n${YELLOW}Firebase service account JSON file(s) found in your project directory.${NC}"
                read -p "Would you like to enable Firebase integration? (y/n): " enable_firebase
                
                if [[ "$enable_firebase" == "y" ]]; then
                    if [ $(echo "$FIREBASE_JSON_FILES" | wc -l) -gt 1 ]; then
                        echo -e "${YELLOW}Multiple Firebase service account JSON files found:${NC}"
                        i=1
                        for file in $FIREBASE_JSON_FILES; do
                            echo "$i) $(basename "$file")"
                            i=$((i+1))
                        done
                        
                        read -p "Select a file number [1-$((i-1))]: " file_num
                        if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -ge 1 ] && [ "$file_num" -le $((i-1)) ]; then
                            SELECTED_FILE=$(echo "$FIREBASE_JSON_FILES" | sed -n "${file_num}p")
                        else
                            echo -e "${YELLOW}Invalid selection. Using the first file.${NC}"
                            SELECTED_FILE=$(echo "$FIREBASE_JSON_FILES" | head -n 1)
                        fi
                    else
                        SELECTED_FILE=$FIREBASE_JSON_FILES
                    fi
                    
                    echo -e "${GREEN}Using Firebase configuration from: $(basename "$SELECTED_FILE")${NC}"
                    
                    # Extract Firebase credentials from JSON file
                    if [ -f "$SELECTED_FILE" ]; then
                        FIREBASE_PROJECT_ID=$(grep -o '"project_id": *"[^"]*"' "$SELECTED_FILE" | sed 's/"project_id": *"\([^"]*\)"/\1/')
                        FIREBASE_PRIVATE_KEY_ID=$(grep -o '"private_key_id": *"[^"]*"' "$SELECTED_FILE" | sed 's/"private_key_id": *"\([^"]*\)"/\1/')
                        FIREBASE_PRIVATE_KEY=$(grep -o '"private_key": *"[^"]*"' "$SELECTED_FILE" | sed 's/"private_key": *"//' | sed 's/"$//')
                        # Ensure proper escaping for .env file
                        FIREBASE_PRIVATE_KEY=$(echo "$FIREBASE_PRIVATE_KEY" | sed 's/\\n/\\\\n/g')
                        FIREBASE_CLIENT_EMAIL=$(grep -o '"client_email": *"[^"]*"' "$SELECTED_FILE" | sed 's/"client_email": *"\([^"]*\)"/\1/')
                        FIREBASE_CLIENT_ID=$(grep -o '"client_id": *"[^"]*"' "$SELECTED_FILE" | sed 's/"client_id": *"\([^"]*\)"/\1/')
                        FIREBASE_CLIENT_X509_CERT_URL=$(grep -o '"client_x509_cert_url": *"[^"]*"' "$SELECTED_FILE" | sed 's/"client_x509_cert_url": *"\([^"]*\)"/\1/')
                        
                        if [ -z "$FIREBASE_PROJECT_ID" ] || [ -z "$FIREBASE_PRIVATE_KEY" ] || [ -z "$FIREBASE_CLIENT_EMAIL" ]; then
                            echo -e "${RED}Could not extract all required fields from the JSON file.${NC}"
                            echo -e "${RED}The file may be incomplete or have an unexpected format.${NC}"
                            echo -e "${YELLOW}Continuing without Firebase integration.${NC}"
                        else
                            # Update .env file with Firebase credentials
                            echo -e "${BLUE}Updating .env file with Firebase credentials...${NC}"
                            
                            # Check if Firebase section already exists in .env
                            grep -q "FIREBASE_PROJECT_ID" "$PROJECT_DIR/.env"
                            if [ $? -eq 0 ]; then
                                # Replace existing Firebase credentials
                                sed -i.bak '/FIREBASE_PROJECT_ID/d' "$PROJECT_DIR/.env"
                                sed -i.bak '/FIREBASE_PRIVATE_KEY_ID/d' "$PROJECT_DIR/.env"
                                sed -i.bak '/FIREBASE_PRIVATE_KEY/d' "$PROJECT_DIR/.env"
                                sed -i.bak '/FIREBASE_CLIENT_EMAIL/d' "$PROJECT_DIR/.env"
                                sed -i.bak '/FIREBASE_CLIENT_ID/d' "$PROJECT_DIR/.env"
                                sed -i.bak '/FIREBASE_CLIENT_X509_CERT_URL/d' "$PROJECT_DIR/.env"
                                rm -f "$PROJECT_DIR/.env.bak"
                            fi
                            
                            # Add Firebase configuration to .env
                            cat >> "$PROJECT_DIR/.env" << EOL

# Firebase configuration
FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
FIREBASE_PRIVATE_KEY_ID=$FIREBASE_PRIVATE_KEY_ID
FIREBASE_PRIVATE_KEY="$FIREBASE_PRIVATE_KEY"
FIREBASE_CLIENT_EMAIL=$FIREBASE_CLIENT_EMAIL
FIREBASE_CLIENT_ID=$FIREBASE_CLIENT_ID
FIREBASE_CLIENT_X509_CERT_URL=$FIREBASE_CLIENT_X509_CERT_URL
EOL
                            
                            INCLUDE_FIREBASE="y"
                            echo -e "${GREEN}Firebase configuration updated successfully.${NC}"
                        fi
                    else
                        echo -e "${RED}Selected file not found or not readable.${NC}"
                        echo -e "${YELLOW}Continuing without Firebase integration.${NC}"
                    fi
                fi
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

    # Choose region with numbered options
    echo -e "\n${YELLOW}Available GCP regions:${NC}"
    echo -e "1) us-central1 (Iowa) - Recommended for US workloads"
    echo -e "2) us-east1 (South Carolina) - Good for US East Coast users"
    echo -e "3) us-west1 (Oregon) - Good for US West Coast users"
    echo -e "4) europe-west1 (Belgium) - Recommended for European workloads"
    echo -e "5) asia-east1 (Taiwan) - Recommended for Asian workloads"
    echo -e "6) Custom region"
    
    read -p "Select a region [1-6, default: 1]: " region_choice
    case $region_choice in
        2) GCP_REGION="us-east1" ;;
        3) GCP_REGION="us-west1" ;;
        4) GCP_REGION="europe-west1" ;;
        5) GCP_REGION="asia-east1" ;;
        6) read -p "Enter custom region: " GCP_REGION ;;
        *) GCP_REGION="us-central1" ;;
    esac
    echo -e "Using region: ${GREEN}$GCP_REGION${NC}"
    
    # Set service name
    echo -e "\n${YELLOW}Cloud Run Service Name:${NC}"
    echo -e "This is the name of your deployed service in Cloud Run. It will be part of your URL."
    read -p "Enter Cloud Run service name [$SERVICE_NAME]: " input_service
    SERVICE_NAME=${input_service:-$SERVICE_NAME}
    echo -e "Using service name: ${GREEN}$SERVICE_NAME${NC}"
    
    # Configure CPU resources
    echo -e "\n${YELLOW}CPU Options:${NC}"
    echo -e "1) 1 CPU (Minimum recommended for n8n)"
    echo -e "2) 2 CPUs (Better for workloads with multiple active workflows)"
    echo -e "3) 4 CPUs (Best for heavy automation workloads)"
    echo -e "4) Custom CPU value"
    
    read -p "Select CPU option [1-4, default: 1]: " cpu_choice
    case $cpu_choice in
        2) CPU=2 ;;
        3) CPU=4 ;;
        4) read -p "Enter custom CPU value: " CPU ;;
        *) CPU=1 ;;
    esac
    echo -e "Using CPU: ${GREEN}$CPU${NC}"
    
    # Configure memory resources
    echo -e "\n${YELLOW}Memory Options:${NC}"
    echo -e "1) 1Gi (Minimum recommended for n8n)"
    echo -e "2) 2Gi (Better for workloads with multiple active workflows)"
    echo -e "3) 4Gi (Best for heavy automation workloads)"
    echo -e "4) Custom memory value"
    
    read -p "Select memory option [1-4, default: 1]: " memory_choice
    case $memory_choice in
        2) MEMORY="2Gi" ;;
        3) MEMORY="4Gi" ;;
        4) read -p "Enter custom memory value (e.g., 512Mi, 1Gi): " MEMORY ;;
        *) MEMORY="1Gi" ;;
    esac
    echo -e "Using memory: ${GREEN}$MEMORY${NC}"
    
    # Configure max instances
    echo -e "\n${YELLOW}Maximum Instance Options:${NC}"
    echo -e "Maximum number of container instances allowed to handle traffic. Higher values allow better scaling but can increase costs."
    echo -e "1) 1 instance (Minimal cost, no scalability)"
    echo -e "2) 5 instances (Default, good balance of scalability and cost)"
    echo -e "3) 10 instances (Better for high traffic scenarios)"
    echo -e "4) Custom max instances"
    
    read -p "Select maximum instances [1-4, default: 2]: " max_choice
    case $max_choice in
        1) MAX_INSTANCES=1 ;;
        3) MAX_INSTANCES=10 ;;
        4) read -p "Enter custom max instances: " MAX_INSTANCES ;;
        *) MAX_INSTANCES=5 ;;
    esac
    echo -e "Using maximum instances: ${GREEN}$MAX_INSTANCES${NC}"
    
    # Configure min instances
    echo -e "\n${YELLOW}Minimum Instance Options:${NC}"
    echo -e "Minimum number of instances to keep running. Higher values reduce cold starts but increase costs."
    echo -e "1) 0 instances (Recommended for cost-sensitive deployments, will scale to zero when not in use)"
    echo -e "2) 1 instance (No cold starts, continuous availability, higher cost)"
    echo -e "3) Custom min instances"
    
    read -p "Select minimum instances [1-3, default: 1]: " min_choice
    case $min_choice in
        2) MIN_INSTANCES=1 ;;
        3) read -p "Enter custom min instances: " MIN_INSTANCES ;;
        *) MIN_INSTANCES=0 ;;
    esac
    echo -e "Using minimum instances: ${GREEN}$MIN_INSTANCES${NC}"
    
    # Configure request timeout
    echo -e "\n${YELLOW}Request Timeout Options:${NC}"
    echo -e "Maximum time a request can take before being terminated. Longer timeouts are needed for workflows that process large files or have many steps."
    echo -e "1) 300s (5 minutes, default for most simple workflows)"
    echo -e "2) 900s (15 minutes, recommended for complex workflows)"
    echo -e "3) 1800s (30 minutes, for very complex workflows)"
    echo -e "4) Custom timeout"
    
    read -p "Select request timeout [1-4, default: 2]: " timeout_choice
    case $timeout_choice in
        1) TIMEOUT="300s" ;;
        3) TIMEOUT="1800s" ;;
        4) read -p "Enter custom timeout in seconds (add 's' suffix): " TIMEOUT ;;
        *) TIMEOUT="900s" ;;
    esac
    echo -e "Using request timeout: ${GREEN}$TIMEOUT${NC}"
    
    # Configure concurrency
    echo -e "\n${YELLOW}Concurrency Options:${NC}"
    echo -e "Maximum number of concurrent requests per container instance. Higher values allow more parallel workflows but require more resources."
    echo -e "1) 40 (Conservative, good for resource-intensive workflows)"
    echo -e "2) 80 (Default, balanced for most workloads)"
    echo -e "3) 120 (Higher, good for many simple workflows)"
    echo -e "4) Custom concurrency"
    
    read -p "Select concurrency level [1-4, default: 2]: " concurrency_choice
    case $concurrency_choice in
        1) CONCURRENCY=40 ;;
        3) CONCURRENCY=120 ;;
        4) read -p "Enter custom concurrency: " CONCURRENCY ;;
        *) CONCURRENCY=80 ;;
    esac
    echo -e "Using concurrency: ${GREEN}$CONCURRENCY${NC}"
    
    # Get domain name (optional)
    echo -e "\n${YELLOW}Custom Domain (Optional):${NC}"
    echo -e "If you have your own domain name, you can use it with your n8n deployment."
    read -p "Enter your custom domain name for n8n (leave blank for none): " input_domain
    DOMAIN_NAME=${input_domain:-$DOMAIN_NAME}
    if [ ! -z "$DOMAIN_NAME" ]; then
        echo -e "Using custom domain: ${GREEN}$DOMAIN_NAME${NC}"
    else
        echo -e "No custom domain specified, will use default Cloud Run URL."
    fi
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
        # For Cloud Run, we'll use a placeholder and update it after deployment
        # with the actual URL. Using a random hash to avoid collisions
        SERVICE_URL="https://$SERVICE_NAME-$(echo $RANDOM | md5sum | head -c 6)-$GCP_REGION.a.run.app"
    else
        SERVICE_URL="https://$DOMAIN_NAME"
    fi
    
    # Set webhook environment variables (critical for proper operation on Cloud Run)
    echo "N8N_HOST: \"${SERVICE_URL#https://}\"" >> $ENV_FILE
    echo "N8N_PROTOCOL: \"https\"" >> $ENV_FILE
    echo "WEBHOOK_URL: \"$SERVICE_URL\"" >> $ENV_FILE
    
    # IMPORTANT: Prevent webhook deregistration on shutdown for serverless
    echo "N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN: \"true\"" >> $ENV_FILE
    
    # Database configuration
    echo "DB_TYPE: \"postgresdb\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_HOST: \"$DB_POSTGRESDB_HOST\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_PORT: \"$DB_POSTGRESDB_PORT\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_DATABASE: \"$DB_POSTGRESDB_DATABASE\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_USER: \"$DB_POSTGRESDB_USER\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_PASSWORD: \"$DB_POSTGRESDB_PASSWORD\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_SCHEMA: \"$DB_POSTGRESDB_SCHEMA\"" >> $ENV_FILE
    echo "DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: \"false\"" >> $ENV_FILE
    
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
    echo -e "${YELLOW}Note: Webhook URLs will be updated with actual Cloud Run URL after deployment${NC}"
}

# Function to create Dockerfile based on Firebase preference
create_dockerfile() {
    echo -e "${BLUE}=== Creating Dockerfile ===${NC}"
    
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
RUN npm install -g firebase-admin

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
    
    # Get the actual service URL after deployment
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform=managed --region=$GCP_REGION --format='value(status.url)')
    
    # Check if deployment was successful
    if [ $? -eq 0 ] && [ ! -z "$SERVICE_URL" ]; then
        echo -e "${GREEN}=== Deployment complete! ===${NC}"
        echo -e "Your n8n instance is available at: ${BLUE}$SERVICE_URL${NC}"
        echo -e "Username: ${BLUE}$N8N_BASIC_AUTH_USER${NC}"
        echo -e "Password: ${BLUE}$N8N_BASIC_AUTH_PASSWORD${NC}"
        
        # Update the webhook URLs with the actual Cloud Run URL
        echo -e "${YELLOW}Updating webhook URLs with actual Cloud Run URL...${NC}"
        gcloud run services update $SERVICE_NAME \
            --region=$GCP_REGION \
            --set-env-vars="WEBHOOK_URL=$SERVICE_URL,N8N_HOST=${SERVICE_URL#https://}"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Webhook URLs updated successfully!${NC}"
        else
            echo -e "${RED}Failed to update webhook URLs. Please update them manually:${NC}"
            echo -e "gcloud run services update $SERVICE_NAME --region=$GCP_REGION --set-env-vars=\"WEBHOOK_URL=$SERVICE_URL,N8N_HOST=${SERVICE_URL#https://}\""
        fi
        
        if [ ! -z "$DOMAIN_NAME" ]; then
            echo -e "${YELLOW}Next Steps for Custom Domain:${NC}"
            echo -e "1. Map your domain to Cloud Run: ${BLUE}gcloud beta run domain-mappings create --service=$SERVICE_NAME --domain=$DOMAIN_NAME --region=$GCP_REGION${NC}"
            echo -e "2. Configure DNS records according to Cloud Run instructions"
        fi
        
        echo -e "${YELLOW}IMPORTANT NOTES FOR WEBHOOKS:${NC}"
        echo -e "1. Webhooks are configured with:"
        echo -e "   - WEBHOOK_URL: ${BLUE}$SERVICE_URL${NC}"
        echo -e "   - N8N_HOST: ${BLUE}${SERVICE_URL#https://}${NC}"
        echo -e "   - N8N_PROTOCOL: https"
        echo -e "   - N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN: true"
        echo -e "2. After first login, recreate any webhook workflows to ensure proper registration"
        echo -e "3. To test a webhook, use: ${BLUE}curl -X POST $SERVICE_URL/webhook/path-to-your-webhook${NC}"
        echo -e "4. If webhooks don't work, check logs: ${BLUE}gcloud run logs read $SERVICE_NAME --region=$GCP_REGION${NC}"
        echo -e "5. Verify webhook settings in n8n UI: Settings → Webhook URLs"
        
        echo -e "${YELLOW}ENCRYPTION KEY:${NC}"
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

# Verify and troubleshoot webhook setup
verify_webhooks() {
    echo -e "${BLUE}=== Webhook Verification Guide ===${NC}"
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform=managed --region=$GCP_REGION --format='value(status.url)')
    
    echo -e "${YELLOW}To ensure webhooks work correctly with Cloud Run, follow these steps:${NC}"
    echo -e "1. Verify environment variables are set correctly:"
    echo -e "   Run: ${BLUE}gcloud run services describe $SERVICE_NAME --region=$GCP_REGION --format='value(spec.template.spec.containers[0].env)'${NC}"
    echo -e "   Confirm you see these variables with correct values:"
    echo -e "   - WEBHOOK_URL = $SERVICE_URL"
    echo -e "   - N8N_HOST = ${SERVICE_URL#https://}"
    echo -e "   - N8N_PROTOCOL = https"
    echo -e "   - N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN = true"
    
    echo -e "\n2. If environment variables need to be updated, run:"
    echo -e "   ${BLUE}gcloud run services update $SERVICE_NAME --region=$GCP_REGION \\${NC}"
    echo -e "   ${BLUE}  --set-env-vars=\"WEBHOOK_URL=$SERVICE_URL,N8N_HOST=${SERVICE_URL#https://},N8N_PROTOCOL=https,N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true\"${NC}"
    
    echo -e "\n3. In n8n UI, create a simple webhook workflow:"
    echo -e "   - Add a Webhook node as trigger (set to 'test-webhook')"
    echo -e "   - Add a Set node to return a simple response"
    echo -e "   - Deploy/activate the workflow"
    
    echo -e "\n4. Test the webhook using curl:"
    echo -e "   ${BLUE}curl -X POST $SERVICE_URL/webhook/test-webhook${NC}"
    
    echo -e "\n5. If the webhook isn't working, check logs:"
    echo -e "   ${BLUE}gcloud run logs read $SERVICE_NAME --region=$GCP_REGION --limit=50${NC}"
    
    echo -e "\n6. Common webhook issues on Cloud Run:"
    echo -e "   - Incorrect URL in environment variables"
    echo -e "   - Webhook deregistration on shutdown (fixed by N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN)"
    echo -e "   - Cloud Run instance cold start timing issues"
    echo -e "   - Permissions issues for the service account"

    echo -e "\n${GREEN}Your deployed n8n instance should now handle webhooks correctly!${NC}"
    echo -e "${YELLOW}If you continue to have issues, try setting MIN_INSTANCES=1 to prevent cold starts${NC}"
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
    verify_webhooks
    cleanup
    
    echo -e "${GREEN}=== Deployment Complete! ===${NC}"
}

# Run main function
main 