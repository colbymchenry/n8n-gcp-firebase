# n8n-gcp-firebase

This repository contains scripts to set up and deploy n8n (nodemation) workflows with Firebase integration on Google Cloud Platform.

## Getting Started

This repository provides three main scripts:
- `setup.sh` - Creates a new n8n project with PostgreSQL and optional Firebase integration
- `docker.sh` - Runs n8n locally in Docker
- `deploy-cloud-run.sh` - Deploys n8n to Google Cloud Run

To get started quickly:

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/n8n-gcp-firebase.git
   cd n8n-gcp-firebase
   ```

2. Make all scripts executable:
   ```bash
   chmod +x setup.sh docker.sh deploy-cloud-run.sh
   ```

## Table of Contents

1. [Local Setup](#local-setup)
   - [Prerequisites](#prerequisites)
   - [Creating a New Project](#creating-a-new-project)
   - [Running Locally](#running-locally)
2. [Cloud Run Deployment](#cloud-run-deployment)
   - [Prerequisites](#cloud-prerequisites)
   - [Setting Up Google Cloud](#setting-up-google-cloud)
   - [Deploying to Cloud Run](#deploying-to-cloud-run)
3. [Webhook Configuration](#webhook-configuration)
4. [Troubleshooting](#troubleshooting)
5. [Firebase Integration](#firebase-integration)
   - [Setting Up Firebase](#setting-up-firebase)
   - [Using Firebase in n8n Workflows](#using-firebase-in-n8n-workflows)

## Local Setup

### Prerequisites

- Docker and Docker Compose installed
- Bash shell environment
- A Neon PostgreSQL account and database (or other PostgreSQL provider)
- (Optional) Firebase project for Firebase integration

### Creating a New Project

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/n8n-gcp-firebase.git
   cd n8n-gcp-firebase
   ```

2. Make the setup script executable:
   ```bash
   chmod +x setup.sh
   ```

3. Run the setup script with your desired project name:
   ```bash
   ./setup.sh my-n8n-project
   ```

   The script will prompt you for:
   - n8n username and password
   - Neon PostgreSQL database details
   - (Optional) Firebase configuration if you want to integrate with Firebase

4. After completion, you'll have a new directory with your project name containing:
   - docker-compose.yml
   - Dockerfile (if Firebase integration was selected)
   - .env file with your configuration
   - README.md with project-specific instructions

### Running Locally

1. Navigate to your project directory:
   ```bash
   cd my-n8n-project
   ```

2. Copy the docker.sh script to your project directory:
   ```bash
   cp ../docker.sh .
   ```

3. Make the docker script executable:
   ```bash
   chmod +x docker.sh
   ```

4. Start n8n using the provided docker script:
   ```bash
   ./docker.sh
   ```

5. Access n8n at [http://localhost:5678](http://localhost:5678) and log in using the credentials you provided during setup.

## Cloud Run Deployment

### Cloud Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (gcloud) installed
- Docker installed
- Neon PostgreSQL database (or other PostgreSQL provider)

### Setting Up Google Cloud

1. Install the Google Cloud CLI if you haven't already:
   ```bash
   # For macOS (using Homebrew)
   brew install --cask google-cloud-sdk

   # For Ubuntu/Debian
   echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
   curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
   sudo apt-get update && sudo apt-get install google-cloud-sdk

   # For other operating systems, see: https://cloud.google.com/sdk/docs/install
   ```

2. Initialize and log in to Google Cloud:
   ```bash
   gcloud init
   ```
   Follow the prompts to log in and select your Google Cloud project.

3. Enable billing for your project (required for Cloud Run):
   ```bash
   gcloud billing projects link YOUR_PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID
   ```
   You can find your billing account ID with `gcloud billing accounts list`.

### Deploying to Cloud Run

1. Make sure you're in the repository root directory (not inside your project folder):
   ```bash
   cd /path/to/n8n-gcp-firebase
   ```

2. Make the deployment script executable:
   ```bash
   chmod +x deploy-cloud-run.sh
   ```

3. Run the deployment script:
   ```bash
   ./deploy-cloud-run.sh
   ```

4. Follow the script prompts to configure your deployment:
   - Select your existing project directory
   - Choose your GCP project and region
   - Configure CPU, memory, and scaling options
   - (Optional) Specify a custom domain

5. After deployment completes, you'll receive:
   - The URL of your n8n instance
   - Your n8n username and password
   - The encryption key (save this for future deployments)
   - Webhook configuration details

## Webhook Configuration

When deploying to Cloud Run, webhooks require special configuration due to the serverless nature of the platform. The `deploy-cloud-run.sh` script handles this automatically by setting:

- `WEBHOOK_URL`: The complete URL to your Cloud Run service
- `N8N_HOST`: The hostname of your Cloud Run service
- `N8N_PROTOCOL`: Set to "https" (always use HTTPS with Cloud Run)
- `N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN`: Set to "true" to maintain webhooks during scaling

After deploying to Cloud Run, you may need to:
1. Log in to your n8n instance
2. Recreate any webhook workflows to ensure proper registration
3. Test your webhooks using the provided curl commands

## Troubleshooting

### Webhook Issues

If webhooks aren't working after deployment:

1. Verify environment variables with:
   ```bash
   gcloud run services describe YOUR_SERVICE_NAME --region=YOUR_REGION --format='value(spec.template.spec.containers[0].env)'
   ```

2. Update environment variables if needed:
   ```bash
   gcloud run services update YOUR_SERVICE_NAME --region=YOUR_REGION \
     --set-env-vars="WEBHOOK_URL=https://your-service-url.a.run.app,N8N_HOST=your-service-url.a.run.app,N8N_PROTOCOL=https,N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true"
   ```

3. Check logs:
   ```bash
   gcloud run logs read YOUR_SERVICE_NAME --region=YOUR_REGION --limit=50
   ```

### Cold Start Issues

If you're experiencing slow response times or webhook failures due to cold starts:

1. Update your Cloud Run service to maintain at least one instance:
   ```bash
   gcloud run services update YOUR_SERVICE_NAME --region=YOUR_REGION --min-instances=1
   ```
   Note: This will prevent scaling to zero and increase costs.

### Database Connection Issues

Ensure your Neon PostgreSQL database (or other provider):
- Has the correct IP allowlist settings for Cloud Run
- Has SSL properly configured
- Has the correct database user permissions

## Firebase Integration

This setup supports Firebase integration with n8n, allowing you to use Firebase services (Firestore, Authentication, etc.) in your n8n workflows.

### Setting Up Firebase

1. Create a Firebase project at [firebase.google.com](https://firebase.google.com)

2. Generate a new private key for your service account:
   - Go to Project Settings > Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file to your project directory

3. During setup, the scripts will automatically:
   - Detect Firebase service account JSON files (named *firebase-adminsdk*.json)
   - Ask if you want to enable Firebase integration
   - Extract all necessary credentials from the JSON file
   - Configure your environment variables automatically

4. If no JSON file is found, you can either:
   - Try again after adding the JSON file
   - Enter the credentials manually
   - Skip Firebase integration

### Using Firebase in n8n Workflows

When creating n8n workflows with Firebase, use the Function node with this template:

```javascript
const admin = require('firebase-admin');

// Create service account from environment variables
const serviceAccount = {
  "type": "service_account",
  "project_id": process.env.FIREBASE_PROJECT_ID,
  "private_key_id": process.env.FIREBASE_PRIVATE_KEY_ID,
  "private_key": process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
  "client_email": process.env.FIREBASE_CLIENT_EMAIL,
  "client_id": process.env.FIREBASE_CLIENT_ID,
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": process.env.FIREBASE_CLIENT_X509_CERT_URL
};

// Initialize Firebase (only if not already initialized)
if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

// Example: Get Firestore document
const db = admin.firestore();
const docRef = db.collection('users').doc('user123');
const doc = await docRef.get();

if (doc.exists) {
  // Document exists, return its data
  return {
    data: doc.data()
  };
} else {
  // Document doesn't exist
  return {
    data: { error: 'Document not found' }
  };
}
```

This integration works both locally and when deployed to Cloud Run.
