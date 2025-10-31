#!/bin/bash
#==============================================================================
# Monitoring Stack - Quick Deploy Script
#==============================================================================
# Simple script for deploying monitoring stack
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   install   - Install Ansible dependencies
#   check     - Check connection to server
#   deploy    - Run deployment
#   status    - Show container status
#   help      - Show help
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INVENTORY="inventory/hosts.ini"
PLAYBOOK="playbooks/setup-monitoring.yml"
REQUIREMENTS="requirements.yml"
VAULT_PASS_FILE=".vault_pass"

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}OK $1${NC}"
}

print_error() {
    echo -e "${RED}X $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO $1${NC}"
}

get_stack_user() {
    local vars_file="inventory/group_vars/monitoring_hosts/vars.yml"
    if [ ! -f "$vars_file" ]; then
        vars_file="inventory/group_vars/monitoring_hosts/vars.yml.example"
    fi

    local user
    user=$(grep -E '^[[:space:]]*monitoring_stack_user:' "$vars_file" 2>/dev/null | head -n1 | cut -d':' -f2 | awk '{print $1}')
    user=${user//\"/}
    user=${user//\'/}

    if [ -z "$user" ]; then
        user="monitoring"
    fi

    echo "$user"
}

check_requirements() {
    print_header "Checking requirements"

    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed!"
        echo "Install Ansible with:"
        echo "  pip3 install ansible"
        exit 1
    fi
    print_success "Ansible installed"

    # Check if inventory exists
    if [ ! -f "$INVENTORY" ]; then
        print_error "Inventory file does not exist: $INVENTORY"
        exit 1
    fi
    print_success "Inventory file exists"

    # Check if inventory is configured (look for active hosts, not commented lines)
    if ! grep -v '^#' "$INVENTORY" | grep -q 'ansible_host='; then
        print_warning "Inventory file is not configured!"
        echo "Edit $INVENTORY and add your server IP address"
        echo "Uncomment and configure the monitoring host line"
        exit 1
    fi
    print_success "Inventory configured"

    # Check if vault password file exists
    if [ ! -f "$VAULT_PASS_FILE" ]; then
        print_error "Vault password file does not exist: $VAULT_PASS_FILE"
        echo ""
        echo "Create vault password file:"
        echo "  cp .vault_pass.example .vault_pass"
        echo "  chmod 600 .vault_pass"
        echo "  # Edit .vault_pass and set strong password"
        echo ""
        echo "Then create vault with secrets:"
        echo "  ansible-vault create inventory/group_vars/monitoring_hosts/vault.yml \\"
        echo "    --vault-password-file .vault_pass"
        echo ""
        echo "To generate passwords use:"
        echo "  ./scripts/generate-secrets.sh"
        exit 1
    fi
    print_success "Vault password file exists"

    # Check if vault.yml exists
    if [ ! -f "inventory/group_vars/monitoring_hosts/vault.yml" ]; then
        print_warning "Vault file does not exist!"
        echo ""
        echo "Create vault with secrets:"
        echo "  1. Generate passwords: ./scripts/generate-secrets.sh"
        echo "  2. Create vault: ansible-vault create inventory/group_vars/monitoring_hosts/vault.yml \\"
        echo "                   --vault-password-file .vault_pass"
        echo "  3. Edit hostnames in inventory/group_vars/monitoring_hosts/vars.yml"
        exit 1
    fi
    print_success "Vault file exists"
}

install_collections() {
    print_header "Installing Ansible collections"
    ansible-galaxy collection install -r "$REQUIREMENTS"
    print_success "Collections installed"
}

check_connection() {
    print_header "Checking connection to server"
    ansible -i "$INVENTORY" monitoring_hosts -m ping \
        --vault-password-file "$VAULT_PASS_FILE"
    print_success "Connection successful"
}

deploy_stack() {
    print_header "Deploying monitoring stack"
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK" \
        --vault-password-file "$VAULT_PASS_FILE" \
        "$@"

    if [ $? -eq 0 ]; then
        print_success "Deployment successful!"
        echo ""
        print_info "Configuration management:"
        echo "  - Secrets: Managed via Ansible Vault"
        echo "  - Location: inventory/group_vars/monitoring_hosts/vault.yml (encrypted)"
        echo ""
        print_info "To update secrets:"
        echo "  ansible-vault edit inventory/group_vars/monitoring_hosts/vault.yml \\"
        echo "    --vault-password-file .vault_pass"
        echo ""
        print_info "Check status: ./deploy.sh status"
    else
        print_error "Deployment failed!"
        exit 1
    fi
}

show_status() {
    print_header "Container status"
    local stack_user
    stack_user=$(get_stack_user)
    ansible -i "$INVENTORY" monitoring_hosts -m shell \
        -a "cd /opt/monitoring/current && docker compose -p monitoring ps" \
        --vault-password-file "$VAULT_PASS_FILE" \
        --become \
        --become-user "$stack_user"
}

setup_github_runner() {
    print_header "Setting up GitHub Actions runner"

    # Check if github_org_url exists in vars.yml
    if ! grep -q "github_org_url:" inventory/group_vars/monitoring_hosts/vars.yml 2>/dev/null; then
        print_error "GitHub organization URL not found in vars.yml!"
        echo ""
        echo "Add the GitHub organization URL to vars file:"
        echo "  Edit: inventory/group_vars/monitoring_hosts/vars.yml"
        echo ""
        echo "Add this line:"
        echo "  github_org_url: \"https://github.com/your-org\""
        echo ""
        exit 1
    fi

    # Check if token exists in vault
    if ! ansible-vault view inventory/group_vars/monitoring_hosts/vault.yml \
        --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null | grep -q "vault_github_runner_token"; then
        print_error "GitHub runner token not found in vault!"
        echo ""
        echo "Get a runner token from:"
        echo "  https://github.com/YOUR_ORG/settings/actions/runners/new"
        echo ""
        echo "Then add it to vault file:"
        echo "  ansible-vault edit inventory/group_vars/monitoring_hosts/vault.yml \\"
        echo "    --vault-password-file .vault_pass"
        echo ""
        echo "Add this line:"
        echo "  vault_github_runner_token: \"YOUR_TOKEN_HERE\""
        exit 1
    fi

    print_info "GitHub runner tokens expire after 60 minutes; generate a fresh token if this step fails."

    ansible-playbook -i "$INVENTORY" playbooks/setup-github-runner.yml \
        --vault-password-file "$VAULT_PASS_FILE" \
        "$@"

    if [ $? -eq 0 ]; then
        print_success "GitHub Actions runner setup complete!"
    else
        print_error "GitHub Actions runner setup failed!"
        exit 1
    fi
}

show_help() {
    cat << EOF
Monitoring Stack - Deploy Script
=================================

Usage: $0 [command] [options]

Commands:
    install         Install Ansible dependencies
    check           Check connection to server
    deploy          Deploy monitoring stack
    deploy-check    Deploy in check mode (dry-run)
    status          Show container status
    secrets         Show secrets configuration instructions
    setup-runner    Setup GitHub Actions self-hosted runner
    help            Show this help

Options:
    -v, --verbose   Verbose output
    -vv             Very verbose output
    -vvv            Debug output

Examples:
    $0 install              # Install dependencies
    $0 check                # Check connection
    $0 deploy               # Run deployment
    $0 deploy -v            # Deployment with verbose output
    $0 status               # Show status

Full workflow:
    1. $0 install           # Install Ansible collections
    2. $0 check             # Check connection to server
    3. $0 deploy            # Run deployment
    4. $0 secrets           # Read secrets configuration instructions
    5. $0 deploy            # Run deployment again with secrets
    6. $0 status            # Check service status
    7. $0 setup-runner      # Optional: Register GitHub Actions runner (token valid 60 minutes)

EOF
}

show_secrets_help() {
    print_header "Secrets configuration"
    cat << EOF

Secrets are managed through Ansible Vault - encrypted YAML file.

---------------------------------------------------------------

1. Generate all passwords:
   ./scripts/generate-secrets.sh

2. Create or edit vault file:
   ansible-vault edit inventory/group_vars/monitoring_hosts/vault.yml \\
     --vault-password-file .vault_pass

3. Copy generated values to vault file

4. Update hostnames for production:
   Edit: inventory/group_vars/monitoring_hosts/vars.yml
   vault_grafana_hostname: "grafana.yourdomain.com"
   vault_graylog_hostname: "graylog.yourdomain.com"
   vault_prometheus_hostname: "prometheus.yourdomain.com"
   vault_registry_hostname: "hub.yourdomain.com"

5. Save and close editor (Ctrl+X in nano)

6. Deploy with new secrets:
   ./deploy.sh deploy

---------------------------------------------------------------

Vault operations:

- View vault (read-only):
  ansible-vault view inventory/group_vars/monitoring_hosts/vault.yml \\
    --vault-password-file .vault_pass

- Edit vault:
  ansible-vault edit inventory/group_vars/monitoring_hosts/vault.yml \\
    --vault-password-file .vault_pass

- Change vault password:
  ansible-vault rekey inventory/group_vars/monitoring_hosts/vault.yml \\
    --vault-password-file .vault_pass

---------------------------------------------------------------

EOF
}

# Main
case "${1:-help}" in
    install)
        check_requirements
        install_collections
        ;;
    check)
        check_requirements
        check_connection
        ;;
    deploy)
        shift
        check_requirements
        deploy_stack "$@"
        ;;
    deploy-check)
        shift
        check_requirements
        deploy_stack --check "$@"
        ;;
    status)
        check_requirements
        show_status
        ;;
    secrets)
        show_secrets_help
        ;;
    setup-runner)
        shift
        check_requirements
        setup_github_runner "$@"
        ;;
    help)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
