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
GCP_PROJECT=$(echo "$SETUP_JSON" | grep -o '"gcp_project": "[^"]*' | cut -d'"' -f4)
GCP_REGION=$(echo "$SETUP_JSON" | grep -o '"gcp_region": "[^"]*' | cut -d'"' -f4)
SERVICE_NAME=$(echo "$SETUP_JSON" | grep -o '"service_name": "[^"]*' | cut -d'"' -f4)
CPU=$(echo "$SETUP_JSON" | grep -o '"cpu": "[^"]*' | cut -d'"' -f4)
MEMORY=$(echo "$SETUP_JSON" | grep -o '"memory": "[^"]*' | cut -d'"' -f4)
MAX_INSTANCES=$(echo "$SETUP_JSON" | grep -o '"max_instances": "[^"]*' | cut -d'"' -f4)
MIN_INSTANCES=$(echo "$SETUP_JSON" | grep -o '"min_instances": "[^"]*' | cut -d'"' -f4)
TIMEOUT=$(echo "$SETUP_JSON" | grep -o '"timeout": "[^"]*' | cut -d'"' -f4)
CONCURRENCY=$(echo "$SETUP_JSON" | grep -o '"concurrency": "[^"]*' | cut -d'"' -f4)
N8N_BASIC_AUTH_USER=$(echo "$SETUP_JSON" | grep -o '"n8n_username": "[^"]*' | cut -d'"' -f4)
N8N_BASIC_AUTH_PASSWORD=$(echo "$SETUP_JSON" | grep -o '"n8n_password": "[^"]*' | cut -d'"' -f4)
NEON_DB_HOST=$(echo "$SETUP_JSON" | grep -o '"neon_db_host": "[^"]*' | cut -d'"' -f4)
NEON_DB_PASSWORD=$(echo "$SETUP_JSON" | grep -o '"neon_db_password": "[^"]*' | cut -d'"' -f4)
NEON_DB_NAME=$(echo "$SETUP_JSON" | grep -o '"neon_db_name": "[^"]*' | cut -d'"' -f4)
NEON_DB_USER=$(echo "$SETUP_JSON" | grep -o '"neon_db_user": "[^"]*' | cut -d'"' -f4)
NEON_DB_SCHEMA=$(echo "$SETUP_JSON" | grep -o '"neon_db_schema": "[^"]*' | cut -d'"' -f4)

# Verify required values
if [ -z "$GCP_PROJECT" ] || [ -z "$GCP_REGION" ] || [ -z "$SERVICE_NAME" ]; then
    echo -e "${RED}Error: Missing required GCP configuration in setup.json.${NC}"
    exit 1
fi

# Set defaults for optional values if not specified
CPU=${CPU:-1}
MEMORY=${MEMORY:-"1Gi"}
MAX_INSTANCES=${MAX_INSTANCES:-5}
MIN_INSTANCES=${MIN_INSTANCES:-0}
TIMEOUT=${TIMEOUT:-"900s"}
CONCURRENCY=${CONCURRENCY:-80}

echo -e "\n${BLUE}=== Deploying to Cloud Run ===${NC}"
echo -e "Project: ${GREEN}$GCP_PROJECT${NC}"
echo -e "Region: ${GREEN}$GCP_REGION${NC}"
echo -e "Service: ${GREEN}$SERVICE_NAME${NC}"
echo -e "Resources: ${GREEN}$CPU CPU, $MEMORY memory${NC}"
echo -e "Scaling: ${GREEN}$MIN_INSTANCES-$MAX_INSTANCES instances${NC}"

# Create env vars file for deployment
ENV_FILE="$PROJECT_NAME/cloud-run-env.yaml"
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

# For Cloud Run, we'll use a placeholder and update it after deployment
SERVICE_URL="https://$SERVICE_NAME-$(echo $RANDOM | md5sum | head -c 6)-$GCP_REGION.a.run.app"

# Set webhook environment variables (critical for proper operation on Cloud Run)
echo "N8N_HOST: \"${SERVICE_URL#https://}\"" >> $ENV_FILE
echo "N8N_PROTOCOL: \"https\"" >> $ENV_FILE
echo "WEBHOOK_URL: \"$SERVICE_URL\"" >> $ENV_FILE

# IMPORTANT: Prevent webhook deregistration on shutdown for serverless
echo "N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN: \"true\"" >> $ENV_FILE

# Database configuration
echo "DB_TYPE: \"postgresdb\"" >> $ENV_FILE
echo "DB_POSTGRESDB_HOST: \"$NEON_DB_HOST\"" >> $ENV_FILE
echo "DB_POSTGRESDB_PORT: \"5432\"" >> $ENV_FILE
echo "DB_POSTGRESDB_DATABASE: \"$NEON_DB_NAME\"" >> $ENV_FILE
echo "DB_POSTGRESDB_USER: \"$NEON_DB_USER\"" >> $ENV_FILE
echo "DB_POSTGRESDB_PASSWORD: \"$NEON_DB_PASSWORD\"" >> $ENV_FILE
echo "DB_POSTGRESDB_SCHEMA: \"$NEON_DB_SCHEMA\"" >> $ENV_FILE
echo "DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: \"false\"" >> $ENV_FILE

# Firebase configuration
INSTALL_FIREBASE=$(echo "$SETUP_JSON" | grep -o '"firebase_admin_sdk": [^,}]*' | cut -d':' -f2 | tr -d ' "')
FIREBASE_CREDENTIALS=$(echo "$SETUP_JSON" | grep -o '"firebase_credentials": "[^"]*' | cut -d'"' -f4)

if [ "$INSTALL_FIREBASE" = "true" ]; then
    echo "FIREBASE_CREDENTIALS: \"$FIREBASE_CREDENTIALS\"" >> $ENV_FILE
fi

# Generate encryption key if not provided
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
echo "N8N_ENCRYPTION_KEY: \"$N8N_ENCRYPTION_KEY\"" >> $ENV_FILE

# Allow external modules
echo "NODE_FUNCTION_ALLOW_EXTERNAL: \"*\"" >> $ENV_FILE

# Timezone
echo "GENERIC_TIMEZONE: \"UTC\"" >> $ENV_FILE

echo -e "${GREEN}Environment variables configured in $ENV_FILE${NC}"

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