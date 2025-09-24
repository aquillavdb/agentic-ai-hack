#!/bin/bash

# Script to create a Service Principal for Azure AI services
# This script creates a service principal with the necessary permissions for the claim manager application

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Azure Service Principal Creation Script${NC}"
echo "========================================"

# Check if Azure CLI is installed and user is logged in
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure. Please run 'az login' first.${NC}"
    exit 1
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo -e "${GREEN}Current Subscription:${NC} $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Prompt for required inputs with defaults
read -p "Enter Service Principal name (default: claim-manager-sp): " SP_NAME
SP_NAME=${SP_NAME:-claim-manager-sp}

read -p "Enter Resource Group name: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}Error: Resource Group name is required.${NC}"
    exit 1
fi

# Verify resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo -e "${RED}Error: Resource Group '$RESOURCE_GROUP' does not exist.${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating Service Principal...${NC}"

# Create Service Principal with Cognitive Services User role
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role "Cognitive Services User" \
    --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    2>/dev/null || {
        echo -e "${YELLOW}Service principal might already exist. Attempting to get existing credentials...${NC}"
        # Try to get existing SP
        SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv)
        if [ -z "$SP_APP_ID" ] || [ "$SP_APP_ID" = "null" ]; then
            echo -e "${RED}Error: Failed to create or find existing service principal.${NC}"
            exit 1
        fi
        # Reset credentials for existing SP
        SP_OUTPUT=$(az ad sp credential reset --id "$SP_APP_ID" 2>/dev/null)
    })

# Extract credentials
SP_APP_ID=$(echo "$SP_OUTPUT" | jq -r '.appId // empty')
SP_PASSWORD=$(echo "$SP_OUTPUT" | jq -r '.password // empty')
SP_TENANT=$(echo "$SP_OUTPUT" | jq -r '.tenant // empty')

# Validate extracted values
if [ -z "$SP_APP_ID" ] || [ -z "$SP_PASSWORD" ] || [ -z "$SP_TENANT" ]; then
    echo -e "${RED}Error: Failed to extract service principal credentials.${NC}"
    echo "Raw output: $SP_OUTPUT"
    exit 1
fi

echo -e "${GREEN}Service Principal created successfully!${NC}"

# Additional role assignments that might be needed
echo -e "${YELLOW}Assigning additional roles...${NC}"

# Assign Cosmos DB Built-in Data Reader role (if needed)
az role assignment create \
    --assignee "$SP_APP_ID" \
    --role "Cosmos DB Built-in Data Reader" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    2>/dev/null || echo -e "${YELLOW}Note: Could not assign Cosmos DB role (may not be needed)${NC}"

# Assign Search Index Data Reader role (if needed)
az role assignment create \
    --assignee "$SP_APP_ID" \
    --role "Search Index Data Reader" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    2>/dev/null || echo -e "${YELLOW}Note: Could not assign Search Index role (may not be needed)${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Service Principal Credentials${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}App ID (Client ID):${NC} $SP_APP_ID"
echo -e "${BLUE}Password (Client Secret):${NC} $SP_PASSWORD"
echo -e "${BLUE}Tenant ID:${NC} $SP_TENANT"
echo ""

# Create .env entries
echo -e "${GREEN}Environment Variables for .env file:${NC}"
echo "============================================"
echo "AZURE_CLIENT_ID=\"$SP_APP_ID\""
echo "AZURE_CLIENT_SECRET=\"$SP_PASSWORD\""
echo "AZURE_TENANT_ID=\"$SP_TENANT\""
echo ""


# Show Docker run command example
echo ""
echo -e "${GREEN}Example Docker run command:${NC}"
echo "============================================"
cat << EOF
docker run -p 8000:8000 \\
    -e AZURE_CLIENT_ID="$SP_APP_ID" \\
    -e AZURE_CLIENT_SECRET="$SP_PASSWORD" \\
    -e AZURE_TENANT_ID="$SP_TENANT" \\
    -e CLAIM_REV_AGENT_ID="\$CLAIM_REV_AGENT_ID" \\
    -e RISK_ANALYZER_AGENT_ID="\$RISK_ANALYZER_AGENT_ID" \\
    -e POLICY_CHECKER_AGENT_ID="\$POLICY_CHECKER_AGENT_ID" \\
    claim-manager:latest
EOF

echo ""
echo -e "${YELLOW}Important Security Notes:${NC}"
echo "- Keep these credentials secure and never commit them to version control"
echo "- Consider using Azure Key Vault for production deployments"
echo "- The service principal has been granted minimal required permissions"
echo ""
echo -e "${GREEN}Setup complete!${NC}"