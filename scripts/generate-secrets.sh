#!/bin/bash
#==============================================================================
# Password Generation Helper Script
#==============================================================================
# Generates all required passwords for monitoring stack
#
# Usage:
#   ./scripts/generate-secrets.sh
#==============================================================================

set -e

echo "+----------------------------------------------------------------+"
echo "|         Monitoring Stack - Password Generator                 |"
echo "+----------------------------------------------------------------+"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "Install with: $2"
        return 1
    fi
    return 0
}

echo "Checking dependencies..."
DEPS_OK=true

if ! check_command "openssl" "system package manager"; then
    DEPS_OK=false
fi

if ! check_command "docker" "https://docs.docker.com/engine/install/"; then
    DEPS_OK=false
fi

if [ "$DEPS_OK" = false ]; then
    echo -e "${RED}Please install missing dependencies and try again${NC}"
    exit 1
fi

echo -e "${GREEN}All dependencies found${NC}"
echo ""

#==============================================================================
# 1. Graylog Password Secret (96 hex chars)
#==============================================================================
echo "----------------------------------------------------------------"
echo "1. GRAYLOG_PASSWORD_SECRET (96 hex characters)"
echo "----------------------------------------------------------------"
GRAYLOG_SECRET=$(openssl rand -hex 48)
echo -e "${GREEN}Generated:${NC}"
echo "$GRAYLOG_SECRET"
echo ""

#==============================================================================
# 2. Graylog Root Password (SHA256)
#==============================================================================
echo "----------------------------------------------------------------"
echo "2. GRAYLOG_ROOT_PASSWORD_SHA2 (SHA256 hash)"
echo "----------------------------------------------------------------"
read -sp "Enter Graylog admin password (min 12 chars): " GRAYLOG_PWD
echo ""

if [ ${#GRAYLOG_PWD} -lt 12 ]; then
    echo -e "${RED}Error: Password must be at least 12 characters${NC}"
    exit 1
fi

GRAYLOG_HASH=$(echo -n "$GRAYLOG_PWD" | sha256sum | cut -d" " -f1)
echo -e "${GREEN}Generated SHA256 hash:${NC}"
echo "$GRAYLOG_HASH"
echo ""

#==============================================================================
# 3. Grafana Admin Password (plain text)
#==============================================================================
echo "----------------------------------------------------------------"
echo "3. GRAFANA_ADMIN_PASSWORD (plain text)"
echo "----------------------------------------------------------------"
read -sp "Enter Grafana admin password (min 12 chars): " GRAFANA_PWD
echo ""

if [ ${#GRAFANA_PWD} -lt 12 ]; then
    echo -e "${RED}Error: Password must be at least 12 characters${NC}"
    exit 1
fi

echo -e "${GREEN}Password set:${NC} [hidden]"
echo ""

#==============================================================================
# 4. Prometheus Admin Password (bcrypt)
#==============================================================================
echo "----------------------------------------------------------------"
echo "4. PROMETHEUS_ADMIN_PASSWORD (bcrypt hash)"
echo "----------------------------------------------------------------"
read -sp "Enter Prometheus admin password (min 12 chars): " PROMETHEUS_PWD
echo ""

if [ ${#PROMETHEUS_PWD} -lt 12 ]; then
    echo -e "${RED}Error: Password must be at least 12 characters${NC}"
    exit 1
fi

echo "Generating bcrypt hash (this may take a moment)..."
PROMETHEUS_HASH=$(docker run --rm caddy:alpine caddy hash-password --plaintext "$PROMETHEUS_PWD" 2>/dev/null)
echo -e "${GREEN}Generated bcrypt hash:${NC}"
echo "$PROMETHEUS_HASH"
echo ""

#==============================================================================
# 5. OpenSearch Admin Password (32 random chars)
#==============================================================================
echo "----------------------------------------------------------------"
echo "5. OPENSEARCH_ADMIN_PASSWORD (32 random characters)"
echo "----------------------------------------------------------------"
OPENSEARCH_PWD=$(LC_ALL=C tr -dc 'A-Za-z0-9_@#%^' < /dev/urandom | head -c32)
echo -e "${GREEN}Generated:${NC}"
echo "$OPENSEARCH_PWD"
echo ""

#==============================================================================
# Summary
#==============================================================================
echo "+----------------------------------------------------------------+"
echo "|                    Generated Secrets Summary                  |"
echo "+----------------------------------------------------------------+"
echo ""
echo "Copy these values to inventory/group_vars/monitoring_hosts/vault.yml:"
echo ""
echo "---"
echo "# Graylog Configuration"
echo "vault_graylog_password_secret: \"$GRAYLOG_SECRET\""
echo "vault_graylog_root_password_sha2: \"$GRAYLOG_HASH\""
echo ""
echo "# Grafana Configuration"
echo "vault_grafana_admin_password: \"$GRAFANA_PWD\""
echo ""
echo "# Prometheus Configuration"
echo "vault_prometheus_admin_password: \"$PROMETHEUS_HASH\""
echo ""
echo "# OpenSearch Configuration"
echo "vault_opensearch_admin_password: \"$OPENSEARCH_PWD\""
echo ""
echo "----------------------------------------------------------------"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Create encrypted vault file:"
echo "   ansible-vault create inventory/group_vars/monitoring_hosts/vault.yml \\"
echo "     --vault-password-file .vault_pass"
echo ""
echo "2. Paste the YAML content above into the vault file"
echo ""
echo "3. Save and exit"
echo ""
echo "4. Update hostnames in inventory/group_vars/monitoring_hosts/vars.yml"
echo "   (Hostnames are public and don't need encryption)"
echo ""
echo "----------------------------------------------------------------"
echo ""
