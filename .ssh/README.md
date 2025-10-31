# SSH Keys for Ansible

This directory contains SSH keys used by Ansible to connect to monitoring servers.

## Setup

### 1. Generate a new SSH key pair (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "monitoring" -f .ssh/monitoring_key
```

This will create:
- `monitoring_key` - private key (automatically ignored by git)
- `monitoring_key.pub` - public key (can be committed to git)

### 2. Add public key to server

**Option A: Using ssh-copy-id (easiest)**
```bash
ssh-copy-id -i .ssh/monitoring_key.pub ubuntu@YOUR_SERVER_IP
```

**Option B: Manually**
```bash
# Copy the public key content
cat .ssh/monitoring_key.pub

# SSH to server and add it to authorized_keys
ssh ubuntu@YOUR_SERVER_IP
echo "PASTE_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Option C: During Hetzner Cloud VM creation**
- Go to Hetzner Cloud Console -> Security -> SSH Keys
- Click "Add SSH Key"
- Paste content of `monitoring_key.pub`
- Select this key when creating the server

### 3. Configure inventory to use this key

The key is already configured in `inventory/hosts.ini.example`:

```ini
[monitoring_hosts:vars]
ansible_ssh_private_key_file=.ssh/monitoring_key
```

Just copy the example and configure your server IP:
```bash
cp inventory/hosts.ini.example inventory/hosts.ini
# Edit inventory/hosts.ini and set YOUR_SERVER_IP
```

### 4. Test connection

```bash
ansible -i inventory/hosts.ini monitoring_hosts -m ping
# or use the helper script:
./deploy.sh check
```

## Security Notes

- Private keys (`monitoring_key`) are automatically ignored by git
- Public keys (`*.pub`) can be safely committed
- Never commit or share private keys
- Set proper permissions: `chmod 600 .ssh/monitoring_key`
- The private key stays local to your machine or is securely shared with team members via password manager

## Multiple Keys

If you need different keys for different environments:

```ini
# inventory/hosts.ini
[monitoring_hosts]
prod-server ansible_host=1.2.3.4 ansible_ssh_private_key_file=.ssh/prod_key
dev-server ansible_host=5.6.7.8 ansible_ssh_private_key_file=.ssh/dev_key
```
