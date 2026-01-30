# GitHub Actions Setup Guide

This guide explains how to configure GitHub Actions to automatically bootstrap BOSH on vSphere and deploy authentik.

## Overview

The workflow automates:
1. **BOSH Bootstrap** - Uses bosh-bootloader (bbl) to deploy a BOSH Director on vSphere
2. **Release Build** - Downloads dependencies and creates the authentik BOSH release
3. **Deployment** - Deploys authentik with PostgreSQL on BOSH

## Prerequisites

### vSphere Requirements

Before running the workflow, ensure your vSphere environment has:

- [ ] vCenter Server 6.7+ accessible from GitHub Actions runners
- [ ] A datacenter configured
- [ ] A cluster with sufficient resources (minimum 8 vCPUs, 16GB RAM)
- [ ] A resource pool for BOSH deployments
- [ ] A datastore with at least 100GB free space
- [ ] A port group/network configured with DHCP or static IPs
- [ ] Folder paths created for:
  - VMs
  - Templates
  - Persistent disks

### Network Requirements

The network must have:
- [ ] Outbound internet access (for downloading releases)
- [ ] A subnet with available IPs for:
  - Jumpbox (1 IP)
  - BOSH Director (1 IP)
  - Authentik VMs (2+ IPs)

**Important:** bbl does NOT create networks on vSphere. You must pre-provision the network.

## Step 1: Configure GitHub Secrets

Navigate to your repository: **Settings → Secrets and variables → Actions**

### Required Secrets

#### vSphere Credentials

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `VSPHERE_VCENTER_USER` | vCenter username | `administrator@vsphere.local` |
| `VSPHERE_VCENTER_PASSWORD` | vCenter password | `your-password` |
| `VSPHERE_VCENTER_IP` | vCenter hostname or IP | `vcenter.example.com` |

#### vSphere Infrastructure

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `VSPHERE_VCENTER_DC` | Datacenter name | `DC1` |
| `VSPHERE_VCENTER_CLUSTER` | Cluster name | `Cluster1` |
| `VSPHERE_VCENTER_RP` | Resource pool path | `Cluster1/Resources/BOSH` |
| `VSPHERE_VCENTER_DS` | Datastore name | `datastore1` |
| `VSPHERE_NETWORK` | Network/Port group name | `VM Network` |

#### Network Configuration

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `VSPHERE_SUBNET_CIDR` | Subnet CIDR | `10.0.0.0/24` |
| `VSPHERE_INTERNAL_GW` | Gateway IP | `10.0.0.1` |
| `VSPHERE_JUMPBOX_IP` | Static IP for jumpbox | `10.0.0.5` |
| `VSPHERE_DIRECTOR_INTERNAL_IP` | Static IP for BOSH Director | `10.0.0.6` |

#### Storage Paths

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `VSPHERE_VCENTER_VMS` | VM folder path | `BOSH/vms` |
| `VSPHERE_VCENTER_TEMPLATES` | Template folder path | `BOSH/templates` |
| `VSPHERE_VCENTER_DISKS` | Disk folder path | `BOSH/disks` |

#### State Encryption

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `BBL_STATE_ENCRYPTION_KEY` | Key for encrypting bbl state | Generate with: `openssl rand -base64 32` |

#### Email Configuration (Optional)

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SMTP_HOST` | SMTP server | `smtp.example.com` |
| `SMTP_PORT` | SMTP port | `587` |
| `SMTP_FROM` | From email address | `authentik@example.com` |

### Generate Encryption Key

```bash
# Generate a secure encryption key
openssl rand -base64 32
```

Copy the output and save it as the `BBL_STATE_ENCRYPTION_KEY` secret.

## Step 2: Configure GitHub Environment

Create an environment for deployment protection:

1. Go to **Settings → Environments**
2. Click **New environment**
3. Name it `production` (or match your workflow input)
4. Configure protection rules:
   - Required reviewers (optional but recommended)
   - Wait timer (optional)
   - Deployment branches (e.g., `main` only)

## Step 3: Prepare vSphere Folders

Create the required folder structure in vSphere:

```
Datacenter
└── vm
    └── BOSH
        ├── vms        ← VSPHERE_VCENTER_VMS
        ├── templates  ← VSPHERE_VCENTER_TEMPLATES
        └── disks      ← VSPHERE_VCENTER_DISKS
```

Using govc (VMware CLI):

```bash
export GOVC_URL="https://vcenter.example.com/sdk"
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_PASSWORD="your-password"
export GOVC_INSECURE=true

govc folder.create /DC1/vm/BOSH
govc folder.create /DC1/vm/BOSH/vms
govc folder.create /DC1/vm/BOSH/templates
govc folder.create /DC1/vm/BOSH/disks
```

## Step 4: Create Resource Pool

Create a resource pool for BOSH:

```bash
govc pool.create /DC1/host/Cluster1/Resources/BOSH
```

## Step 5: Run the Workflow

### Deploy Everything (BOSH + Authentik)

1. Go to **Actions** tab
2. Select **Deploy Authentik on BOSH/vSphere**
3. Click **Run workflow**
4. Select options:
   - **Action:** `deploy`
   - **Environment:** `production`
   - **Authentik version:** `2025.12.1`
5. Click **Run workflow**

### Deploy Only BOSH Director

Use action: `bosh-only`

### Deploy Only Authentik (if BOSH already exists)

Use action: `authentik-only`

### Destroy Everything

Use action: `destroy`

⚠️ **Warning:** This will delete all VMs and data!

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Workflow                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │  bootstrap-bosh  │    │   build-release  │                   │
│  │                  │    │                  │                   │
│  │  • Install tools │    │  • Download deps │                   │
│  │  • Run bbl up    │    │  • Build release │                   │
│  │  • Save state    │    │  • Upload artifact│                  │
│  └────────┬─────────┘    └────────┬─────────┘                   │
│           │                       │                              │
│           └───────────┬───────────┘                              │
│                       ▼                                          │
│           ┌──────────────────────┐                               │
│           │   deploy-authentik   │                               │
│           │                      │                               │
│           │  • Load BOSH env     │                               │
│           │  • Upload stemcell   │                               │
│           │  • Upload releases   │                               │
│           │  • Deploy manifest   │                               │
│           └──────────────────────┘                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        vSphere                                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Jumpbox   │  │    BOSH     │  │       Authentik         │  │
│  │             │  │   Director  │  │  ┌─────────┐ ┌────────┐ │  │
│  │ SSH Access  │  │             │  │  │ Server  │ │ Worker │ │  │
│  │             │  │  Manages →  │  │  │         │ │        │ │  │
│  └─────────────┘  └─────────────┘  │  └─────────┘ └────────┘ │  │
│                                    │  ┌─────────────────────┐ │  │
│                                    │  │     PostgreSQL      │ │  │
│                                    │  └─────────────────────┘ │  │
│                                    └─────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## State Management

### How BBL State is Stored

The workflow stores BBL state as an encrypted GitHub artifact:

1. After `bbl up`, the state is encrypted with AES-256-CBC
2. The encrypted state is uploaded as an artifact
3. Subsequent runs download and decrypt the state

### State Retention

- Artifacts are retained for 90 days by default
- For long-term storage, consider:
  - Storing state in an encrypted S3 bucket
  - Using GitHub's encrypted secrets for small state files
  - Setting up a dedicated state storage solution

### Recovering State

If you lose the artifact, you'll need to:

1. Manually recreate the bbl-state directory
2. Or run `bbl destroy` and `bbl up` again

## Troubleshooting

### Common Issues

#### "Cannot connect to vCenter"

- Verify `VSPHERE_VCENTER_IP` is reachable from GitHub Actions
- Check firewall rules allow outbound HTTPS (443) to vCenter
- Verify credentials are correct

#### "Network not found"

- Ensure `VSPHERE_NETWORK` matches the exact port group name
- Check the network is in the correct datacenter

#### "Insufficient resources"

- Verify the cluster has enough CPU/RAM
- Check datastore free space
- Ensure resource pool limits aren't exceeded

#### "BBL state not found"

- Check if the artifact expired (90-day retention)
- Verify the environment name matches previous deployments

### Debug Mode

To enable verbose logging, the workflow uses `bbl up --debug`. Check the workflow logs for detailed output.

### Manual Recovery

If the workflow fails, you can SSH to the jumpbox:

```bash
# Get SSH key from bbl state
cd bbl-state
bbl ssh-key > jumpbox.pem
chmod 600 jumpbox.pem

# SSH to jumpbox
ssh -i jumpbox.pem jumpbox@<JUMPBOX_IP>

# From jumpbox, access BOSH director
bosh -e <DIRECTOR_IP> --ca-cert <(bbl director-ca-cert) alias-env bosh
export BOSH_CLIENT=$(bbl director-username)
export BOSH_CLIENT_SECRET=$(bbl director-password)
bosh -e bosh vms
```

## Security Considerations

1. **Secrets:** All sensitive values are stored as GitHub Secrets
2. **State Encryption:** BBL state is encrypted before storage
3. **Environment Protection:** Use GitHub Environments for approval workflows
4. **Network Isolation:** Consider using a dedicated network for BOSH
5. **Credential Rotation:** Regularly rotate vCenter credentials

## Cost Optimization

The default VM sizes can be adjusted in the workflow:

```yaml
# In cloud-config-ops.yml
cpu: 2      # Reduce for dev environments
ram: 4096   # Adjust based on workload
disk: 20480 # Persistent disk size in MB
```

## Next Steps

After deployment:

1. Access authentik at `http://<AUTHENTIK_IP>:9000`
2. Complete initial setup at `/if/flow/initial-setup/`
3. Configure SSO providers
4. Set up MFA policies
5. Integrate applications

## References

- [bosh-bootloader Documentation](https://github.com/cloudfoundry/bosh-bootloader)
- [vSphere Getting Started](https://github.com/cloudfoundry/bosh-bootloader/blob/main/docs/getting-started-vsphere.md)
- [BOSH Documentation](https://bosh.io/docs/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
