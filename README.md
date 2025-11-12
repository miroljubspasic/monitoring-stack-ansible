# Monitoring Stack - Ansible Deployment

Production-ready Ansible automation for deploying a complete monitoring infrastructure on Hetzner Cloud or any Ubuntu/Debian server.

## Features

- **Automated Infrastructure Setup**
  - Docker CE installation from official repository
  - User and permission management
  - Persistent data directories with proper ACLs

- **Monitoring Stack Components** (deployed via Docker Compose)
  - Caddy (reverse proxy with automatic HTTPS)
  - Prometheus (metrics collection and alerting)
  - Grafana (metrics visualization and dashboards)
  - Graylog (centralized log management)
  - OpenSearch (log storage backend)
  - Docker Registry (private image repository)

- **Security Features**
  - Ansible Vault for secrets encryption
  - Dedicated SSH keys for deployment
  - Non-root user for service execution
  - Automatic HTTPS certificate management

- **Deployment Management**
  - Rolling releases with automatic cleanup
  - Idempotent playbooks (safe to run multiple times)
  - Health checks and verification
  - Easy rollback to previous releases

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/miroljubspasic/docker-monitoring-stack.git
cd docker-monitoring-stack/ansible

# 2. Install Ansible collections
./deploy.sh install

# 3. Configure your environment
cp inventory/hosts.ini.example inventory/hosts.ini
cp inventory/group_vars/monitoring_hosts/vars.yml.example inventory/group_vars/monitoring_hosts/vars.yml
cp .vault_pass.example .vault_pass

# Edit configuration files
vim inventory/hosts.ini                                      # Set server IP
vim inventory/group_vars/monitoring_hosts/vars.yml          # Set domain names
vim .vault_pass                                              # Set vault password

# 4. Generate secrets and create vault
./scripts/generate-secrets.sh
ansible-vault create inventory/group_vars/monitoring_hosts/vault.yml --vault-password-file .vault_pass
# Copy generated secrets into vault

# 5. Setup SSH access
ssh-keygen -t ed25519 -f .ssh/monitoring_key
ssh-copy-id -i .ssh/monitoring_key.pub root@YOUR_SERVER_IP

# 6. Test connection and deploy
./deploy.sh check
./deploy.sh deploy
```

After a successful run the playbooks create the non-root service account defined by `monitoring_stack_user` (default `monitoring`). Use that account for day-to-day maintenance once it exists.

## Prerequisites

### Local Machine
- Ansible 2.13+ (`pip3 install ansible`)
- Python 3.8+
- SSH client

### Target Server
- Ubuntu 24.04 LTS (recommended) or Debian 12+
- Minimum 4GB RAM (8GB+ recommended for production)
- Minimum 40GB disk space
- Root or sudo access via SSH
- Public IP address with DNS records configured

### Network Requirements
- Outbound: HTTPS access for package downloads and Docker images
- Inbound: Ports 80 and 443 for web services

## Detailed Setup

### 1. Initial Configuration

#### Inventory Setup
Copy the example inventory and configure your server:

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
```

Edit `inventory/hosts.ini`:
```ini
[monitoring_hosts]
monitoring-1 ansible_host=YOUR_SERVER_IP ansible_user=root ansible_port=22

[monitoring_hosts:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=.ssh/monitoring_key
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
```

#### Variables Configuration
Copy and configure the variables file:

```bash
cp inventory/group_vars/monitoring_hosts/vars.yml.example inventory/group_vars/monitoring_hosts/vars.yml
```

Edit `inventory/group_vars/monitoring_hosts/vars.yml`:
```yaml
# Production Hostnames - Configure your DNS before deployment
vault_registry_hostname: "hub.yourdomain.com"
vault_prometheus_hostname: "prometheus.yourdomain.com"
vault_grafana_hostname: "grafana.yourdomain.com"
vault_graylog_hostname: "graylog.yourdomain.com"

# System user created during deployment
monitoring_stack_user: "monitoring"
monitoring_stack_group: "monitoring"
monitoring_stack_user_groups:
  - sudo
  - docker

# GitHub Runner (optional)
github_org_url: "https://github.com/your-org"
```

By default the playbooks connect to each host as `root`, create the user defined by `monitoring_stack_user`, grant the listed groups (sudo and docker by default), and then run all services as that non-root account. Adjust these values before your first deployment if you want a different service user.

### 2. Secrets Management

#### Setup Vault Password
```bash
cp .vault_pass.example .vault_pass
chmod 600 .vault_pass
# Edit .vault_pass and set a strong password (min 20 characters)
```

#### Generate Secrets
```bash
./scripts/generate-secrets.sh
```

This generates all required passwords. Save the output.

#### Create Encrypted Vault
```bash
ansible-vault create inventory/group_vars/monitoring_hosts/vault.yml \
  --vault-password-file .vault_pass
```

Add the generated secrets to the vault file:
```yaml
---
# Graylog
vault_graylog_password_secret: "PASTE_96_CHAR_SECRET"
vault_graylog_root_password_sha2: "PASTE_SHA256_HASH"

# Grafana
vault_grafana_admin_password: "YourStrongPassword123"

# Prometheus
vault_prometheus_admin_password: "PASTE_BCRYPT_HASH"

# OpenSearch
vault_opensearch_admin_password: "PASTE_32_CHAR_STRING"
```

### 3. SSH Key Setup

Generate a dedicated SSH key for Ansible:
```bash
ssh-keygen -t ed25519 -C "monitoring-deployment" -f .ssh/monitoring_key
```

Copy the public key to your server:
```bash
ssh-copy-id -i .ssh/monitoring_key.pub root@YOUR_SERVER_IP
```

Test the connection:
```bash
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP
```

### 4. DNS Configuration

Before deployment, configure DNS A records pointing to your server IP:
- `hub.yourdomain.com` -> Server IP
- `prometheus.yourdomain.com` -> Server IP
- `grafana.yourdomain.com` -> Server IP
- `graylog.yourdomain.com` -> Server IP

Verify DNS propagation:
```bash
dig +short hub.yourdomain.com
```

### 5. Deploy

#### Install Dependencies
```bash
./deploy.sh install
```

#### Check Connectivity
```bash
./deploy.sh check
```

#### Run Deployment
```bash
./deploy.sh deploy
```

For verbose output:
```bash
./deploy.sh deploy -vv
```

For dry-run (check mode):
```bash
./deploy.sh deploy-check
```

## Post-Deployment

### Verify Services

Check that all containers are running:
```bash
./deploy.sh status
```

### Access Services

- **Grafana**: https://grafana.yourdomain.com
  - Username: `admin`
  - Password: (from vault: `vault_grafana_admin_password`)

- **Prometheus**: https://prometheus.yourdomain.com
  - Username: `admin`
  - Password: (from vault: `vault_prometheus_admin_password`)

- **Graylog**: https://graylog.yourdomain.com
  - Username: `admin`
  - Password: (SHA2 hash source from vault setup)

- **Docker Registry**: https://hub.yourdomain.com

### Check Logs

```bash
# On the server
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP
cd /opt/monitoring/current
docker compose logs -f
```

## GitHub Actions Runner Setup (Optional)

Deploy self-hosted GitHub Actions runners on **dedicated servers** (separate from monitoring stack).

### Overview

Runners are deployed to the `runner_hosts` inventory group with their own configuration:
- **Inventory group:** `[runner_hosts]` in `inventory/hosts.ini`
- **Configuration:** `inventory/group_vars/runner_hosts/`
- **Playbook:** `playbooks/setup-github-runner.yml`
- **Documentation:** See [RUNNER_SETUP.md](RUNNER_SETUP.md) for detailed guide

### Quick Setup

1. **Add server to inventory** (`inventory/hosts.ini`):
   ```ini
   [runner_hosts]
   giz-runner ansible_host=159.69.41.252 ansible_user=root
   ```

2. **Configure variables:**
   ```bash
   cp inventory/group_vars/runner_hosts/vars.yml.example \
      inventory/group_vars/runner_hosts/vars.yml
   vim inventory/group_vars/runner_hosts/vars.yml
   ```

   Set:
   ```yaml
   github_org_url: "https://github.com/your-org"
   ```

3. **Get GitHub runner token** (valid 60 minutes):
   - Organization: `https://github.com/YOUR_ORG/settings/actions/runners/new`
   - Repository: `https://github.com/YOUR_ORG/YOUR_REPO/settings/actions/runners/new`

4. **Create encrypted vault:**
   ```bash
   ansible-vault create inventory/group_vars/runner_hosts/vault.yml \
     --vault-password-file .vault_pass
   ```

   Add token:
   ```yaml
   vault_github_runner_token: "YOUR_REGISTRATION_TOKEN"
   ```

5. **Deploy runner:**
   ```bash
   ./deploy.sh setup-runner
   ```

The runner will appear in your GitHub organization's settings as `{hostname}-runner`.

📖 **Full documentation:** [RUNNER_SETUP.md](RUNNER_SETUP.md)

## Project Structure

```
.
|-- .ssh/                          # SSH keys (git-ignored)
|   |-- monitoring_key            # Private key
|   |-- monitoring_key.pub        # Public key
|   \-- README.md                 # SSH setup guide
|
|-- inventory/
|   |-- hosts.ini                 # Server inventory (git-ignored)
|   |-- hosts.ini.example         # Template for hosts
|   \-- group_vars/
|       |-- monitoring_hosts/     # Monitoring stack config
|       |   |-- vars.yml          # Public config (git-ignored)
|       |   |-- vars.yml.example  # Template
|       |   |-- vault.yml         # Encrypted secrets (git-ignored)
|       |   \-- vault.yml.example # Template
|       \-- runner_hosts/         # GitHub runner config
|           |-- vars.yml.example  # Template
|           \-- vault.yml.example # Template
|
|-- playbooks/
|   |-- setup-monitoring.yml      # Monitoring stack deployment (targets: monitoring_hosts)
|   \-- setup-github-runner.yml   # GitHub runner setup (targets: runner_hosts)
|
|-- templates/
|   \-- production.env.j2         # Docker Compose environment template
|
|-- scripts/
|   \-- generate-secrets.sh       # Password generation helper
|
|-- deploy.sh                      # Main deployment script
|-- requirements.yml               # Ansible Galaxy dependencies
|-- RUNNER_SETUP.md                # GitHub runner detailed guide
\-- .vault_pass                    # Vault password (git-ignored)
```

## Common Operations

### Update Secrets
```bash
ansible-vault edit inventory/group_vars/monitoring_hosts/vault.yml \
  --vault-password-file .vault_pass
```

### Re-deploy After Config Changes
```bash
./deploy.sh deploy
```

### Restart a Service
```bash
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP \
  "cd /opt/monitoring/current && docker compose restart grafana"
```

### View Service Logs
```bash
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP \
  "cd /opt/monitoring/current && docker compose logs -f prometheus"
```

### Check Container Status
```bash
./deploy.sh status
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to server
```bash
./deploy.sh check
# Error: Could not connect
```

**Solution**:
1. Verify SSH key is added: `ssh-add -l`
2. Test manual SSH: `ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP`
3. Check firewall: Ensure port 22 is open
4. Verify IP in `inventory/hosts.ini`

### Vault Password Issues

**Problem**: Wrong vault password
```bash
# ERROR! Decryption failed
```

**Solution**:
1. Verify password in `.vault_pass` file
2. Try manual decryption: `ansible-vault view inventory/group_vars/monitoring_hosts/vault.yml`

### Container Not Starting

**Problem**: Service container not running

**Solution**:
```bash
# SSH to server
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP

# Check logs
cd /opt/monitoring/current
docker compose logs SERVICE_NAME

# Check permissions
ls -la /opt/monitoring/

# Restart service
docker compose restart SERVICE_NAME
```

### DNS Issues

**Problem**: Cannot access services via domain

**Solution**:
1. Verify DNS records: `dig +short yourdomain.com`
2. Check Caddy logs: `docker compose logs caddy`
3. Verify domains in `vars.yml` match DNS records
4. Wait for DNS propagation (up to 48 hours)

### Permission Denied

**Problem**: Permission denied errors during deployment

**Solution**:
1. Verify user has sudo access
2. Check user is in docker group (replace `monitoring` with your `monitoring_stack_user` value): `groups monitoring`
3. Re-deploy to fix permissions: `./deploy.sh deploy`

## Maintenance

### Backup

Important data locations on server:
- `/opt/monitoring/prometheus/data` - Metrics data
- `/opt/monitoring/graylog/data` - Log data
- `/opt/monitoring/grafana/data` - Dashboards and settings

Create backups:
```bash
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP
# Replace /home/monitoring with the home directory of monitoring_stack_user if changed
sudo tar -czf /home/monitoring/monitoring-backup-$(date +%Y%m%d).tar.gz \
  /opt/monitoring/prometheus/data \
  /opt/monitoring/graylog/data \
  /opt/monitoring/grafana
```

### Updates

To update the monitoring stack:
```bash
./deploy.sh deploy
```

This will:
1. Pull latest code from repository
2. Create a new release
3. Update containers
4. Keep last 3 releases for rollback

### Rollback

If deployment fails, rollback to previous release:
```bash
ssh -i .ssh/monitoring_key root@YOUR_SERVER_IP
cd /opt/monitoring/releases
ls -lt  # Find previous release
sudo ln -sfn /opt/monitoring/releases/PREVIOUS_TIMESTAMP /opt/monitoring/current
cd /opt/monitoring/current
docker compose up -d
```

## Security Best Practices

1. **Keep Secrets Secure**
   - Never commit `.vault_pass`, `vault.yml`, or SSH private keys
   - Use strong vault passwords (20+ characters)
   - Rotate secrets regularly

2. **SSH Key Management**
   - Use dedicated SSH keys for deployment
   - Protect private keys: `chmod 600 .ssh/monitoring_key`
   - Consider using SSH agent forwarding

3. **Network Security**
   - Use firewall to restrict access (ufw, iptables)
   - Enable fail2ban for SSH protection
   - Use VPN for administrative access

4. **Regular Updates**
   - Keep server packages updated: `apt update && apt upgrade`
   - Monitor security advisories
   - Update Docker images regularly

## Development

### Running in Check Mode (Dry Run)
```bash
./deploy.sh deploy-check
```

### Verbose Output
```bash
./deploy.sh deploy -vvv
```

### Testing Inventory
```bash
ansible-inventory -i inventory/hosts.ini --list
```

### Validating Playbooks
```bash
ansible-playbook playbooks/setup-monitoring.yml --syntax-check
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

For issues, questions, or contributions:
- Repository: https://github.com/your-org/monitoring-stack
- Issues: https://github.com/your-org/monitoring-stack/issues

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Last Updated**: October 2024
**Ansible Version**: 2.13+
**Tested On**: Ubuntu 22.04 LTS, Debian 11
