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

echo -e "\n${BLUE}=== Initializing GCP configuration ===${NC}"
    
# Get GCP project
current_project=$(gcloud config get-value project 2>/dev/null)

# List available projects
echo -e "${YELLOW}Available GCP Projects:${NC}"
projects=($(gcloud projects list --format="value(projectId)"))

if [ ${#projects[@]} -eq 0 ]; then
  echo -e "${RED}No projects found. Please create a GCP project first.${NC}"
  exit 1
fi

# Function to display projects
display_projects() {
  for i in "${!projects[@]}"; do
    project_num=$((i+1))
    if [ "${projects[$i]}" == "$current_project" ]; then
      echo -e "$project_num) ${projects[$i]} ${GREEN}(current)${NC}"
    else
      echo -e "$project_num) ${projects[$i]}"
    fi
  done
  echo -e "$((${#projects[@]}+1)) Custom project ID"
}

# Loop until valid project is selected
while true; do
  display_projects
  
  # Get user selection
  read -p "Select a project [1-$((${#projects[@]}+1)), default: current]: " project_choice
  
  if [ -z "$project_choice" ]; then
    # Use current project if available
    GCP_PROJECT=$current_project
    break
  elif [ "$project_choice" -eq "$((${#projects[@]}+1))" ] 2>/dev/null; then
    # Custom project option
    read -p "Enter custom GCP project ID: " custom_project
    if [ -n "$custom_project" ]; then
      GCP_PROJECT=$custom_project
      break
    else
      echo -e "${RED}Error: Custom project ID cannot be empty.${NC}"
      continue
    fi
  elif [ "$project_choice" -ge 1 ] 2>/dev/null && [ "$project_choice" -le "${#projects[@]}" ] 2>/dev/null; then
    # Valid selection from list
    GCP_PROJECT=${projects[$((project_choice-1))]}
    break
  else
    # Invalid selection, prompt again
    echo -e "${RED}Invalid selection. Please choose a valid option.${NC}"
    continue
  fi
done

if [ -z "$GCP_PROJECT" ]; then
  echo -e "${RED}Error: No project specified.${NC}"
  exit 1
fi

SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$GCP_PROJECT" '. + {gcp_project: $val}')

# Set the project in gcloud config
echo "Setting project to: $GCP_PROJECT"
gcloud config set project "$GCP_PROJECT"

# Choose region with numbered options
echo -e "\n${YELLOW}Available GCP regions:${NC}"
regions=(
  "africa-south1"
  "asia-east1"
  "asia-east2"
  "asia-northeast1"
  "asia-northeast2"
  "asia-northeast3"
  "asia-south1"
  "asia-south2"
  "asia-southeast1"
  "asia-southeast2"
  "australia-southeast1"
  "australia-southeast2"
  "europe-central2"
  "europe-north1"
  "europe-north2"
  "europe-southwest1"
  "europe-west1"
  "europe-west10"
  "europe-west12"
  "europe-west2"
  "europe-west3"
  "europe-west4"
  "europe-west6"
  "europe-west8"
  "europe-west9"
  "me-central1"
  "me-central2"
  "me-west1"
  "northamerica-northeast1"
  "northamerica-northeast2"
  "northamerica-south1"
  "southamerica-east1"
  "southamerica-west1"
  "us-central1"
  "us-east1"
  "us-east4"
  "us-east5"
  "us-south1"
  "us-west1"
  "us-west2"
  "us-west3"
  "us-west4"
)

# Display all regions with numbers
for i in "${!regions[@]}"; do
  echo -e "$((i+1))) ${regions[$i]}"
done
echo -e "$((${#regions[@]}+1)) Custom region"

# Get user selection
read -p "Select a region [1-$((${#regions[@]}+1)), default: 34 (us-central1)]: " region_choice

if [ -z "$region_choice" ]; then
  # Default to us-central1
  GCP_REGION="us-central1"
elif [ "$region_choice" -eq "$((${#regions[@]}+1))" ] 2>/dev/null; then
  # Custom region option
  read -p "Enter custom region: " GCP_REGION
elif [ "$region_choice" -ge 1 ] 2>/dev/null && [ "$region_choice" -le "${#regions[@]}" ] 2>/dev/null; then
  # Valid selection from list
  GCP_REGION=${regions[$((region_choice-1))]}
else
  # Invalid selection, use default
  echo -e "${RED}Invalid selection. Using default region.${NC}"
  GCP_REGION="us-central1"
fi

echo -e "Using region: ${GREEN}$GCP_REGION${NC}"
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$GCP_REGION" '. + {gcp_region: $val}')

# Set service name
SERVICE_NAME=$PROJECT_NAME
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$SERVICE_NAME" '. + {service_name: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$CPU" '. + {cpu: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$MEMORY" '. + {memory: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$MAX_INSTANCES" '. + {max_instances: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$MIN_INSTANCES" '. + {min_instances: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$TIMEOUT" '. + {timeout: $val}')

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
# Add to JSON
SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$CONCURRENCY" '. + {concurrency: $val}')

# Get domain name (optional)
echo -e "\n${YELLOW}Custom Domain (Optional):${NC}"
echo -e "If you have your own domain name, you can use it with your n8n deployment."
read -p "Enter your custom domain name for n8n (leave blank for none): " input_domain
DOMAIN_NAME=${input_domain:-$DOMAIN_NAME}
if [ ! -z "$DOMAIN_NAME" ]; then
    echo -e "Using custom domain: ${GREEN}$DOMAIN_NAME${NC}"
    # Add to JSON
    SETUP_JSON=$(echo $SETUP_JSON | jq --arg val "$DOMAIN_NAME" '. + {domain_name: $val}')
else
    echo -e "No custom domain specified, will use default Cloud Run URL."
fi

# Save setup.json file
echo $SETUP_JSON | jq '.' > "$PROJECT_NAME/setup.json"

# Run the setup_postgres script
if [ -f "./setup_docker.sh" ]; then
    chmod +x ./setup_docker.sh
    ./setup_docker.sh "$PROJECT_NAME"
else
    echo -e "${RED}Error: setup_docker.sh script not found.${NC}"
    exit 1
fi