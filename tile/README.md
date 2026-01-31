# Authentik Tile for Tanzu Operations Manager

This directory contains the tile packaging for deploying Authentik to Tanzu Operations Manager.

## Prerequisites

- Tanzu Operations Manager 2.10+
- BOSH CLI v2
- wget or curl
- zip utility
- Blobs downloaded (run `../scripts/download-blobs.sh` first)

## Building the Tile

```bash
# First, ensure blobs are downloaded
cd ..
./scripts/download-blobs.sh

# Build the tile
cd tile
./build-tile.sh
```

The tile will be created at `output/authentik-<version>.pivotal`.

### Build Options

```bash
# Specify a custom version
./build-tile.sh --version 2025.12.2

# Use a custom output directory
./build-tile.sh --output-dir /path/to/output

# Skip building the BOSH release (use existing tarball)
./build-tile.sh --skip-release-build

# Skip downloading BPM and Postgres releases
./build-tile.sh --skip-dependency-download
```

## Installing the Tile

### Using the Ops Manager UI

1. Log into Tanzu Operations Manager
2. Click **Import a Product** on the left sidebar
3. Select the `.pivotal` file
4. Click the **+** button next to the Authentik tile to stage it
5. Click on the **Authentik** tile to configure it
6. Configure the required settings (see Configuration section below)
7. Return to the Installation Dashboard and click **Review Pending Changes**
8. Select Authentik and click **Apply Changes**

### Using the OM CLI

```bash
# Upload the tile
om -t https://opsmgr.example.com -u admin -p password \
   upload-product -p output/authentik-2025.12.1.pivotal

# Stage the product
om -t https://opsmgr.example.com -u admin -p password \
   stage-product -p authentik -v 2025.12.1

# Configure the product
om -t https://opsmgr.example.com -u admin -p password \
   configure-product -c sample-config.yml

# Apply changes
om -t https://opsmgr.example.com -u admin -p password \
   apply-changes --product-name authentik
```

## Configuration

The tile provides configuration forms for:

### Authentik Configuration
- Secret key (auto-generated if not provided)
- Log level (debug, info, warning, error)
- Cookie domain
- Update check settings
- User impersonation settings

### Database Configuration
- **Internal**: Uses an embedded PostgreSQL database
- **External**: Connect to an existing PostgreSQL server

### Email (SMTP) Configuration
- SMTP server settings for sending emails
- TLS/SSL options
- Authentication credentials

### Storage Configuration
- **File**: Local filesystem storage for media
- **S3**: S3-compatible object storage

### Web Server Configuration
- Worker and thread counts
- HTTP/HTTPS ports
- Metrics port for Prometheus

### Worker Configuration
- Background task concurrency

### Cache Configuration
- Cache timeouts for various components

### Outpost Configuration
- Enable LDAP, RADIUS, or Proxy outposts
- Outpost authentication token

## Post-Installation

After the tile is deployed:

1. Access Authentik at `https://<vm-ip>:9443`
2. Complete the initial setup wizard at `/if/flow/initial-setup/`
3. Create your admin account
4. Configure identity providers and applications

### Configuring Outposts

If you enabled outposts:

1. Log into the Authentik admin interface
2. Navigate to **Applications > Outposts**
3. Create an outpost and copy the token
4. Update the tile configuration with the outpost token
5. Apply changes

## Smoke Tests

The tile includes a smoke test errand that runs automatically after deployment. It verifies:

- HTTP/HTTPS health endpoints
- API availability
- Database connectivity
- Static asset serving
- Prometheus metrics endpoint

To run smoke tests manually:

```bash
bosh -d authentik run-errand smoke-tests
```

## Troubleshooting

### Viewing Logs

```bash
# SSH into the Authentik server
bosh -d authentik ssh authentik-server

# View server logs
sudo tail -f /var/vcap/sys/log/authentik-server/*.log

# View worker logs
sudo tail -f /var/vcap/sys/log/authentik-worker/*.log
```

### Common Issues

1. **Database connection errors**: Verify PostgreSQL credentials and network connectivity
2. **SMTP errors**: Check SMTP server settings and firewall rules
3. **Outpost connection issues**: Ensure the outpost token is valid and authentik.host is accessible

## Directory Structure

```
tile/
├── build-tile.sh           # Tile build script
├── metadata/
│   └── metadata.yml        # Tile metadata and configuration
├── content_migrations/
│   └── content_migrations.yml
├── migrations/
│   └── v1/
│       └── 202501301200_initial.js
├── sample-config.yml       # Sample OM CLI configuration
└── README.md               # This file
```

## Support

For issues with this tile, please open an issue on the GitHub repository.
