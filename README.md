# BOSH Release for Authentik

[![Deploy Authentik on BOSH/vSphere](https://github.com/nkuhn-vmw/bosh-authentik/actions/workflows/deploy.yml/badge.svg)](https://github.com/nkuhn-vmw/bosh-authentik/actions/workflows/deploy.yml)

This BOSH release deploys [authentik](https://goauthentik.io/), an open-source Identity Provider (IdP) supporting SAML, OAuth2/OIDC, LDAP, RADIUS, and more.

This release runs authentik **natively** without Docker, packaging Python and all dependencies directly.

## Quick Start with GitHub Actions

The fastest way to deploy is using our automated GitHub Actions workflow:

1. Fork this repository
2. Configure [GitHub Secrets](docs/GITHUB_ACTIONS_SETUP.md#step-1-configure-github-secrets) for your vSphere environment
3. Run the workflow: **Actions → Deploy Authentik on BOSH/vSphere → Run workflow**

This will automatically:
- Bootstrap a BOSH Director on vSphere using [bosh-bootloader](https://github.com/cloudfoundry/bosh-bootloader)
- Build the authentik release with all dependencies
- Deploy authentik with PostgreSQL

See the [GitHub Actions Setup Guide](docs/GITHUB_ACTIONS_SETUP.md) for detailed instructions.

## Components

### Core Jobs
- **authentik-server**: Main web server providing UI and API endpoints (Gunicorn + Uvicorn)
- **authentik-worker**: Background task processor

### Outpost Jobs
- **authentik-ldap-outpost**: LDAP/LDAPS protocol provider (Go binary)
- **authentik-radius-outpost**: RADIUS protocol provider (Go binary)
- **authentik-proxy-outpost**: Forward auth reverse proxy (Go binary)

### Packages
- **python3**: Python 3.12 runtime
- **authentik**: Authentik application and Python dependencies
- **authentik-outpost-ldap**: LDAP outpost binary
- **authentik-outpost-radius**: RADIUS outpost binary
- **authentik-outpost-proxy**: Proxy outpost binary

## Requirements

This release requires:

- [bpm-release](https://github.com/cloudfoundry/bpm-release) - BOSH Process Manager
- A PostgreSQL database (e.g., [postgres-release](https://github.com/cloudfoundry/postgres-release))
- Ubuntu Jammy stemcell

## Building the Release

### 1. Download Blobs

Run the helper script to download Python:

```bash
./scripts/download-blobs.sh
```

Then manually download:

**Authentik source and dependencies:**
```bash
# Clone authentik
git clone https://github.com/goauthentik/authentik.git
cd authentik
git checkout 2025.12.1

# Download Python dependencies as wheels
pip download -d ../blobs/authentik/vendor -r requirements.txt

# Create source tarball
tar czf ../blobs/authentik/authentik-2025.12.1.tar.gz .

# Build frontend
cd web
npm ci
npm run build
tar czf ../../blobs/authentik/web-dist.tar.gz dist/
```

**Outpost binaries** from [GitHub releases](https://github.com/goauthentik/authentik/releases):
- `authentik-ldap_linux_amd64` → `blobs/outposts/ldap/`
- `authentik-radius_linux_amd64` → `blobs/outposts/radius/`
- `authentik-proxy_linux_amd64` → `blobs/outposts/proxy/`

### 2. Add Blobs

```bash
# Python
bosh add-blob blobs/python/Python-3.12.4.tar.xz python/Python-3.12.4.tar.xz
bosh add-blob blobs/python/setuptools-70.0.0.tar.gz python/setuptools-70.0.0.tar.gz
bosh add-blob blobs/python/pip-24.0.tar.gz python/pip-24.0.tar.gz

# Authentik
bosh add-blob blobs/authentik/authentik-2025.12.1.tar.gz authentik/authentik-2025.12.1.tar.gz
bosh add-blob blobs/authentik/web-dist.tar.gz authentik/web-dist.tar.gz

# Add all vendor wheels
for wheel in blobs/authentik/vendor/*.whl; do
  bosh add-blob "$wheel" "authentik/vendor/$(basename $wheel)"
done

# Outposts
bosh add-blob blobs/outposts/ldap/authentik-ldap_linux_amd64 outposts/ldap/authentik-ldap_linux_amd64
bosh add-blob blobs/outposts/radius/authentik-radius_linux_amd64 outposts/radius/authentik-radius_linux_amd64
bosh add-blob blobs/outposts/proxy/authentik-proxy_linux_amd64 outposts/proxy/authentik-proxy_linux_amd64
```

### 3. Create and Upload Release

```bash
bosh create-release --force
bosh upload-release
```

## Deployment

### Quick Start

1. Upload dependencies:

```bash
bosh upload-release https://bosh.io/d/github.com/cloudfoundry/bpm-release
bosh upload-release https://bosh.io/d/github.com/cloudfoundry/postgres-release
```

2. Deploy:

```bash
bosh -d authentik deploy manifests/authentik.yml \
  -v smtp_host=smtp.example.com \
  -v smtp_port=587 \
  -v smtp_from=authentik@example.com
```

### Configuration

#### Required Properties

| Property | Description |
|----------|-------------|
| `authentik.secret_key` | Secret key for signing (auto-generated via CredHub) |
| `postgresql.host` | PostgreSQL host (or use database link) |
| `postgresql.password` | PostgreSQL password |

#### Server Properties

| Property | Default | Description |
|----------|---------|-------------|
| `port` | `9000` | HTTP port |
| `https_port` | `9443` | HTTPS port |
| `metrics_port` | `9300` | Prometheus metrics port |
| `web.workers` | `2` | Gunicorn workers |
| `web.threads` | `4` | Threads per worker |
| `log_level` | `info` | Log level (debug, info, warning, error) |
| `disable_update_check` | `true` | Disable update check |
| `disable_startup_analytics` | `true` | Disable analytics |

#### Worker Properties

| Property | Default | Description |
|----------|---------|-------------|
| `worker.concurrency` | `2` | Concurrent task workers |

#### Email Properties

| Property | Default | Description |
|----------|---------|-------------|
| `email.host` | `localhost` | SMTP server |
| `email.port` | `25` | SMTP port |
| `email.username` | | SMTP username |
| `email.password` | | SMTP password |
| `email.use_tls` | `false` | Enable TLS |
| `email.use_ssl` | `false` | Enable SSL |
| `email.from` | `authentik@localhost` | From address |

#### Storage Properties

| Property | Default | Description |
|----------|---------|-------------|
| `storage.media.backend` | `file` | Storage backend (file or s3) |
| `storage.s3.region` | | S3 region |
| `storage.s3.endpoint` | | S3 endpoint URL |
| `storage.s3.access_key` | | S3 access key |
| `storage.s3.secret_key` | | S3 secret key |
| `storage.s3.bucket_name` | | S3 bucket name |

## Operations Files

| File | Description |
|------|-------------|
| `use-external-postgres.yml` | Connect to an external PostgreSQL database |
| `use-s3-storage.yml` | Use S3 for media storage |
| `scale-authentik.yml` | Scale authentik for HA |
| `add-ldap-outpost.yml` | Add LDAP outpost |
| `add-radius-outpost.yml` | Add RADIUS outpost |
| `add-proxy-outpost.yml` | Add proxy outpost |

### Examples

**External database:**
```bash
bosh deploy manifests/authentik.yml \
  -o operations/use-external-postgres.yml \
  -v postgres_host=my-db.example.com \
  -v postgres_password=secret
```

**High availability:**
```bash
bosh deploy manifests/authentik.yml \
  -o operations/scale-authentik.yml \
  -v authentik_instances=3
```

**Add LDAP outpost:**
```bash
# First create outpost in authentik UI and get token
bosh deploy manifests/authentik.yml \
  -o operations/add-ldap-outpost.yml \
  -v authentik_ldap_outpost_token=<token>
```

## Using BOSH Links

This release supports BOSH links for database connectivity:

```yaml
jobs:
  - name: authentik-server
    release: authentik
    consumes:
      database: {from: postgres}
    provides:
      authentik: {as: authentik}

  - name: authentik-ldap-outpost
    release: authentik
    consumes:
      authentik: {from: authentik}
```

## Accessing Authentik

After deployment, authentik is available at:

- HTTP: `http://<instance-ip>:9000`
- HTTPS: `https://<instance-ip>:9443`

Initial setup: Navigate to `/if/flow/initial-setup/` to create the admin user.

## Protocol Ports

| Protocol | Port | Description |
|----------|------|-------------|
| HTTP | 9000 | Web UI and API |
| HTTPS | 9443 | Web UI and API (TLS) |
| LDAP | 3389 | LDAP directory services |
| LDAPS | 6636 | LDAP over TLS |
| RADIUS | 1812 | RADIUS authentication |
| Metrics | 9300 | Prometheus metrics |

## Monitoring

Authentik exposes Prometheus metrics on port 9300:

```yaml
scrape_configs:
  - job_name: authentik
    static_configs:
      - targets: ['authentik.example.com:9300']
```

## Troubleshooting

### View logs
```bash
bosh ssh authentik/0 -c "sudo tail -f /var/vcap/sys/log/authentik-server/*"
bosh ssh authentik/0 -c "sudo tail -f /var/vcap/sys/log/authentik-worker/*"
```

### Check process status
```bash
bosh ssh authentik/0 -c "sudo /var/vcap/jobs/bpm/bin/bpm list"
```

### Run migrations manually
```bash
bosh ssh authentik/0
source /var/vcap/jobs/authentik-server/config/env.sh
cd /var/vcap/packages/authentik
python -m manage migrate
```

### Restart services
```bash
bosh restart authentik
```

## Upgrading

To upgrade authentik:

1. Download new version blobs
2. Update blob references
3. Create new release version
4. Deploy

```bash
bosh create-release --force --version=X.Y.Z
bosh upload-release
bosh deploy manifests/authentik.yml
```

## Documentation

- [Getting Started Guide](docs/GETTING_STARTED.md) - Step-by-step manual deployment
- [GitHub Actions Setup](docs/GITHUB_ACTIONS_SETUP.md) - Automated CI/CD deployment on vSphere

## License

Apache License 2.0

## References

- [Authentik Documentation](https://docs.goauthentik.io/)
- [Authentik GitHub](https://github.com/goauthentik/authentik)
- [BOSH Documentation](https://bosh.io/docs/)
- [bosh-bootloader](https://github.com/cloudfoundry/bosh-bootloader) - BOSH Director bootstrapping
