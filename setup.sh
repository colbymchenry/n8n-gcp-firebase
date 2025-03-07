#!/bin/bash

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== N8N with Neon PostgreSQL Setup ===${NC}"

# Get project name
read -p "Enter project name: " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "Project name cannot be empty. Exiting."
    exit 1
fi

# Create directory with project name
PROJECT_DIR="$PROJECT_NAME"
if [ -d "$PROJECT_DIR" ]; then
    read -p "Directory $PROJECT_DIR already exists. Overwrite? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ]; then
        echo "Setup cancelled. Exiting."
        exit 1
    fi
else
    mkdir -p "$PROJECT_DIR"
fi

# Get n8n credentials
read -p "Enter n8n username [admin]: " N8N_USER
N8N_USER=${N8N_USER:-admin}

read -p "Enter n8n password: " N8N_PASSWORD
echo ""
if [ -z "$N8N_PASSWORD" ]; then
    echo "n8n password cannot be empty. Using default 'password123!'."
    N8N_PASSWORD="password123!"
fi

# Neon database info - prompt for host and password
echo -e "\n${BLUE}Neon PostgreSQL Configuration:${NC}"
read -p "Enter Neon DB host (e.g., ep-example-123456.us-east-2.aws.neon.tech): " NEON_DB_HOST
if [ -z "$NEON_DB_HOST" ]; then
    echo "Neon DB host cannot be empty. Exiting."
    exit 1
fi

read -s -p "Enter Neon DB password: " NEON_DB_PASSWORD
echo ""
if [ -z "$NEON_DB_PASSWORD" ]; then
    echo "Neon DB password cannot be empty. Exiting."
    exit 1
fi

# Use defaults for other DB settings but allow override
read -p "Enter Neon DB name [neondb]: " NEON_DB_NAME_INPUT
NEON_DB_NAME=${NEON_DB_NAME_INPUT:-neondb}

read -p "Enter Neon DB user [neondb_owner]: " NEON_DB_USER_INPUT
NEON_DB_USER=${NEON_DB_USER_INPUT:-neondb_owner}

read -p "Enter Neon DB schema [public]: " NEON_DB_SCHEMA_INPUT
NEON_DB_SCHEMA=${NEON_DB_SCHEMA_INPUT:-public}

# Ask if Firebase Admin should be included
echo -e "\n${BLUE}Firebase Configuration:${NC}"
read -p "Do you want to include Firebase Admin? (y/n): " INCLUDE_FIREBASE
INCLUDE_FIREBASE=$(echo "$INCLUDE_FIREBASE" | tr '[:upper:]' '[:lower:]')

# Firebase variables
FIREBASE_PROJECT_ID=""
FIREBASE_PRIVATE_KEY_ID=""
FIREBASE_PRIVATE_KEY=""
FIREBASE_CLIENT_EMAIL=""
FIREBASE_CLIENT_ID=""
FIREBASE_CLIENT_X509_CERT_URL=""

if [ "$INCLUDE_FIREBASE" = "y" ]; then
    echo -e "${YELLOW}Please enter Firebase credentials:${NC}"
    
    read -p "Firebase Project ID: " FIREBASE_PROJECT_ID
    if [ -z "$FIREBASE_PROJECT_ID" ]; then
        echo "Firebase Project ID cannot be empty. Using placeholder 'your-project-id'."
        FIREBASE_PROJECT_ID="your-project-id"
    fi
    
    read -p "Firebase Private Key ID: " FIREBASE_PRIVATE_KEY_ID
    if [ -z "$FIREBASE_PRIVATE_KEY_ID" ]; then
        echo "Firebase Private Key ID cannot be empty. Using placeholder 'your-private-key-id'."
        FIREBASE_PRIVATE_KEY_ID="your-private-key-id"
    fi
    
    read -p "Firebase Private Key (formatted with newlines as \n): " FIREBASE_PRIVATE_KEY
    if [ -z "$FIREBASE_PRIVATE_KEY" ]; then
        echo "Firebase Private Key cannot be empty. Using placeholder."
        FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYour long private key here\n-----END PRIVATE KEY-----\n"
    fi
    
    read -p "Firebase Client Email: " FIREBASE_CLIENT_EMAIL
    if [ -z "$FIREBASE_CLIENT_EMAIL" ]; then
        echo "Firebase Client Email cannot be empty. Using placeholder 'your-client-email'."
        FIREBASE_CLIENT_EMAIL="your-client-email"
    fi
    
    read -p "Firebase Client ID: " FIREBASE_CLIENT_ID
    if [ -z "$FIREBASE_CLIENT_ID" ]; then
        echo "Firebase Client ID cannot be empty. Using placeholder 'your-client-id'."
        FIREBASE_CLIENT_ID="your-client-id"
    fi
    
    read -p "Firebase Client X509 Cert URL: " FIREBASE_CLIENT_X509_CERT_URL
    if [ -z "$FIREBASE_CLIENT_X509_CERT_URL" ]; then
        echo "Firebase Client X509 Cert URL cannot be empty. Using placeholder 'your-client-x509-cert-url'."
        FIREBASE_CLIENT_X509_CERT_URL="your-client-x509-cert-url"
    fi
fi

# Create .env file with or without Firebase variables
cat > "$PROJECT_DIR/.env" << EOL
# n8n authentication
N8N_BASIC_AUTH_USER=$N8N_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
EOL

# Add Firebase configuration to .env if included
if [ "$INCLUDE_FIREBASE" = "y" ]; then
    cat >> "$PROJECT_DIR/.env" << EOL

# Firebase configuration
FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
FIREBASE_PRIVATE_KEY_ID=$FIREBASE_PRIVATE_KEY_ID
FIREBASE_PRIVATE_KEY="$FIREBASE_PRIVATE_KEY"
FIREBASE_CLIENT_EMAIL=$FIREBASE_CLIENT_EMAIL
FIREBASE_CLIENT_ID=$FIREBASE_CLIENT_ID
FIREBASE_CLIENT_X509_CERT_URL=$FIREBASE_CLIENT_X509_CERT_URL
EOL
fi

# Add PostgreSQL configuration to .env
cat >> "$PROJECT_DIR/.env" << EOL

# PostgreSQL configuration
DB_POSTGRESDB_DATABASE=$NEON_DB_NAME
DB_POSTGRESDB_HOST=$NEON_DB_HOST
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_USER=$NEON_DB_USER
DB_POSTGRESDB_PASSWORD=$NEON_DB_PASSWORD
DB_POSTGRESDB_SCHEMA=$NEON_DB_SCHEMA
EOL

# Create docker-compose.yml based on whether Firebase is included
if [ "$INCLUDE_FIREBASE" = "y" ]; then
    # Version with Firebase
    cat > "$PROJECT_DIR/docker-compose.yml" << EOL
version: "3.8"

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
      - NODE_FUNCTION_ALLOW_EXTERNAL=firebase-admin
      - GENERIC_TIMEZONE=UTC
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - FIREBASE_PROJECT_ID=\${FIREBASE_PROJECT_ID}
      - FIREBASE_PRIVATE_KEY_ID=\${FIREBASE_PRIVATE_KEY_ID}
      - FIREBASE_PRIVATE_KEY=\${FIREBASE_PRIVATE_KEY}
      - FIREBASE_CLIENT_EMAIL=\${FIREBASE_CLIENT_EMAIL}
      - FIREBASE_CLIENT_ID=\${FIREBASE_CLIENT_ID}
      - FIREBASE_CLIENT_X509_CERT_URL=\${FIREBASE_CLIENT_X509_CERT_URL}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      
      # PostgreSQL configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
      - DB_POSTGRESDB_SCHEMA=\${DB_POSTGRESDB_SCHEMA:-public}
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOL

    # Create Dockerfile for Firebase
    cat > "$PROJECT_DIR/Dockerfile" << EOL
# Use the official n8n Docker image as the base
FROM n8nio/n8n:latest

# Switch to root user to install packages
USER root

# Install firebase-admin in the n8n modules directory
WORKDIR /usr/local/lib/node_modules/n8n
RUN npm install firebase-admin

# Revert to the n8n user
USER node
EOL

    # Create README with Firebase
    cat > "$PROJECT_DIR/README.md" << EOL
# $PROJECT_NAME

This is an n8n setup with Firebase Admin and Neon PostgreSQL integration.

## Getting Started

1. Make sure you have Docker and Docker Compose installed
2. Start the application:
   \`\`\`
   docker-compose up -d --build
   \`\`\`
3. Access n8n at http://localhost:5678
4. Login with the credentials set in the .env file

## Configuration

- The application uses Neon PostgreSQL for data persistence
- Firebase Admin is installed for integration with Firebase services
- Data is persisted in a Docker volume named n8n_data

## Examples

To use Firebase Admin in n8n Function nodes:

\`\`\`javascript
const admin = require('firebase-admin');

// Create service account object from environment variables
const serviceAccount = {
  "type": "service_account",
  "project_id": process.env.FIREBASE_PROJECT_ID,
  "private_key_id": process.env.FIREBASE_PRIVATE_KEY_ID,
  "private_key": process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\\n'),
  "client_email": process.env.FIREBASE_CLIENT_EMAIL,
  "client_id": process.env.FIREBASE_CLIENT_ID,
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": process.env.FIREBASE_CLIENT_X509_CERT_URL
};

// Initialize Firebase Admin
if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

// Your Firebase code here
\`\`\`
EOL

else
    # Version without Firebase
    cat > "$PROJECT_DIR/docker-compose.yml" << EOL
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - GENERIC_TIMEZONE=UTC
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      
      # PostgreSQL configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
      - DB_POSTGRESDB_SCHEMA=\${DB_POSTGRESDB_SCHEMA:-public}
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOL

    # Create README without Firebase
    cat > "$PROJECT_DIR/README.md" << EOL
# $PROJECT_NAME

This is an n8n setup with Neon PostgreSQL integration.

## Getting Started

1. Make sure you have Docker and Docker Compose installed
2. Start the application:
   \`\`\`
   docker-compose up -d
   \`\`\`
3. Access n8n at http://localhost:5678
4. Login with the credentials set in the .env file

## Configuration

- The application uses Neon PostgreSQL for data persistence
- Data is persisted in a Docker volume named n8n_data
EOL
fi

echo -e "${GREEN}Setup completed!${NC}"
echo -e "Your n8n project has been created in the ${BLUE}$PROJECT_DIR${NC} directory."
echo -e "To start n8n:"
echo -e "  cd $PROJECT_DIR"
if [ "$INCLUDE_FIREBASE" = "y" ]; then
    echo -e "  docker-compose up -d --build"
else
    echo -e "  docker-compose up -d"
fi
echo -e "Then access n8n at ${BLUE}http://localhost:5678${NC}"
echo -e "Login with username: ${BLUE}$N8N_USER${NC} and your password"