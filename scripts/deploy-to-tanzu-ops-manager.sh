#!/bin/bash
#
# Deploy Authentik BOSH Release to Tanzu Operations Manager
#
# This script deploys the Authentik identity provider to an existing
# Tanzu Operations Manager environment by leveraging the Ops Manager's
# BOSH Director.
#
# Prerequisites:
#   - Tanzu Operations Manager installed and configured
#   - 'om' CLI installed (https://github.com/pivotal-cf/om)
#   - 'bosh' CLI installed (https://bosh.io/docs/cli-v2-install/)
#   - 'jq' installed for JSON parsing
#   - Network access to Ops Manager and BOSH Director
#
# Usage:
#   ./deploy-to-tanzu-ops-manager.sh [options]
#
# Options:
#   --ops-manager-url       Ops Manager URL (or set OM_TARGET)
#   --ops-manager-username  Ops Manager username (or set OM_USERNAME)
#   --ops-manager-password  Ops Manager password (or set OM_PASSWORD)
#   --skip-ssl-validation   Skip SSL certificate validation
#   --deployment-name       BOSH deployment name (default: authentik)
#   --authentik-version     Authentik version to deploy (default: 2025.12.1)
#   --use-external-postgres Use external PostgreSQL database
#   --postgres-host         External PostgreSQL host
#   --postgres-port         External PostgreSQL port (default: 5432)
#   --postgres-user         External PostgreSQL user
#   --postgres-password     External PostgreSQL password
#   --postgres-database     External PostgreSQL database name
#   --use-s3-storage        Use S3 for media storage
#   --s3-region             S3 region
#   --s3-endpoint           S3 endpoint (for S3-compatible storage)
#   --s3-bucket             S3 bucket name
#   --s3-access-key         S3 access key
#   --s3-secret-key         S3 secret key
#   --add-ldap-outpost      Deploy LDAP outpost
#   --add-radius-outpost    Deploy RADIUS outpost
#   --add-proxy-outpost     Deploy Proxy outpost
#   --outpost-token         Token for outpost authentication
#   --scale-instances       Number of authentik instances (default: 1)
#   --smtp-host             SMTP server host
#   --smtp-port             SMTP server port
#   --smtp-from             SMTP from address
#   --dry-run               Show what would be done without making changes
#   --help                  Show this help message
#
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
DEPLOYMENT_NAME="authentik"
AUTHENTIK_VERSION="${AUTHENTIK_VERSION:-2025.12.1}"
SKIP_SSL_VALIDATION=""
DRY_RUN=false

# Optional configurations
USE_EXTERNAL_POSTGRES=false
USE_S3_STORAGE=false
ADD_LDAP_OUTPOST=false
ADD_RADIUS_OUTPOST=false
ADD_PROXY_OUTPOST=false
SCALE_INSTANCES=1

# External PostgreSQL defaults
POSTGRES_PORT=5432
POSTGRES_SSLMODE="require"

# SMTP defaults
SMTP_HOST="localhost"
SMTP_PORT=25
SMTP_FROM="authentik@localhost"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Print colored message
#######################################
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

#######################################
# Show usage information
#######################################
show_help() {
    head -50 "$0" | grep -E "^#" | tail -n +3 | sed 's/^# \?//'
    exit 0
}

#######################################
# Check required dependencies
#######################################
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v om &> /dev/null; then
        missing_deps+=("om")
    fi

    if ! command -v bosh &> /dev/null; then
        missing_deps+=("bosh")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Installation instructions:"
        echo "  om:   https://github.com/pivotal-cf/om/releases"
        echo "  bosh: https://bosh.io/docs/cli-v2-install/"
        echo "  jq:   https://stedolan.github.io/jq/download/"
        exit 1
    fi

    log_success "All dependencies are installed"
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ops-manager-url)
                OM_TARGET="$2"
                shift 2
                ;;
            --ops-manager-username)
                OM_USERNAME="$2"
                shift 2
                ;;
            --ops-manager-password)
                OM_PASSWORD="$2"
                shift 2
                ;;
            --skip-ssl-validation)
                SKIP_SSL_VALIDATION="--skip-ssl-validation"
                shift
                ;;
            --deployment-name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            --authentik-version)
                AUTHENTIK_VERSION="$2"
                shift 2
                ;;
            --use-external-postgres)
                USE_EXTERNAL_POSTGRES=true
                shift
                ;;
            --postgres-host)
                POSTGRES_HOST="$2"
                shift 2
                ;;
            --postgres-port)
                POSTGRES_PORT="$2"
                shift 2
                ;;
            --postgres-user)
                POSTGRES_USER="$2"
                shift 2
                ;;
            --postgres-password)
                POSTGRES_PASSWORD="$2"
                shift 2
                ;;
            --postgres-database)
                POSTGRES_DATABASE="$2"
                shift 2
                ;;
            --postgres-sslmode)
                POSTGRES_SSLMODE="$2"
                shift 2
                ;;
            --use-s3-storage)
                USE_S3_STORAGE=true
                shift
                ;;
            --s3-region)
                S3_REGION="$2"
                shift 2
                ;;
            --s3-endpoint)
                S3_ENDPOINT="$2"
                shift 2
                ;;
            --s3-bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            --s3-access-key)
                S3_ACCESS_KEY="$2"
                shift 2
                ;;
            --s3-secret-key)
                S3_SECRET_KEY="$2"
                shift 2
                ;;
            --add-ldap-outpost)
                ADD_LDAP_OUTPOST=true
                shift
                ;;
            --add-radius-outpost)
                ADD_RADIUS_OUTPOST=true
                shift
                ;;
            --add-proxy-outpost)
                ADD_PROXY_OUTPOST=true
                shift
                ;;
            --outpost-token)
                OUTPOST_TOKEN="$2"
                shift 2
                ;;
            --scale-instances)
                SCALE_INSTANCES="$2"
                shift 2
                ;;
            --smtp-host)
                SMTP_HOST="$2"
                shift 2
                ;;
            --smtp-port)
                SMTP_PORT="$2"
                shift 2
                ;;
            --smtp-from)
                SMTP_FROM="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#######################################
# Validate configuration
#######################################
validate_config() {
    log_info "Validating configuration..."

    # Check Ops Manager credentials
    if [[ -z "${OM_TARGET:-}" ]]; then
        log_error "Ops Manager URL is required. Set OM_TARGET or use --ops-manager-url"
        exit 1
    fi

    if [[ -z "${OM_USERNAME:-}" ]]; then
        log_error "Ops Manager username is required. Set OM_USERNAME or use --ops-manager-username"
        exit 1
    fi

    if [[ -z "${OM_PASSWORD:-}" ]]; then
        log_error "Ops Manager password is required. Set OM_PASSWORD or use --ops-manager-password"
        exit 1
    fi

    # Validate external PostgreSQL config
    if [[ "$USE_EXTERNAL_POSTGRES" == "true" ]]; then
        local pg_missing=()
        [[ -z "${POSTGRES_HOST:-}" ]] && pg_missing+=("--postgres-host")
        [[ -z "${POSTGRES_USER:-}" ]] && pg_missing+=("--postgres-user")
        [[ -z "${POSTGRES_PASSWORD:-}" ]] && pg_missing+=("--postgres-password")
        [[ -z "${POSTGRES_DATABASE:-}" ]] && pg_missing+=("--postgres-database")

        if [ ${#pg_missing[@]} -ne 0 ]; then
            log_error "External PostgreSQL enabled but missing: ${pg_missing[*]}"
            exit 1
        fi
    fi

    # Validate S3 config
    if [[ "$USE_S3_STORAGE" == "true" ]]; then
        local s3_missing=()
        [[ -z "${S3_BUCKET:-}" ]] && s3_missing+=("--s3-bucket")
        [[ -z "${S3_ACCESS_KEY:-}" ]] && s3_missing+=("--s3-access-key")
        [[ -z "${S3_SECRET_KEY:-}" ]] && s3_missing+=("--s3-secret-key")

        if [ ${#s3_missing[@]} -ne 0 ]; then
            log_error "S3 storage enabled but missing: ${s3_missing[*]}"
            exit 1
        fi
    fi

    # Validate outpost config
    if [[ "$ADD_LDAP_OUTPOST" == "true" || "$ADD_RADIUS_OUTPOST" == "true" || "$ADD_PROXY_OUTPOST" == "true" ]]; then
        if [[ -z "${OUTPOST_TOKEN:-}" ]]; then
            log_warning "Outpost(s) enabled but --outpost-token not provided."
            log_warning "You will need to configure the token in authentik UI after initial deployment."
        fi
    fi

    log_success "Configuration validated"
}

#######################################
# Connect to Ops Manager and extract BOSH credentials
#######################################
setup_bosh_environment() {
    log_info "Connecting to Tanzu Operations Manager..."

    # Export OM credentials for om CLI
    export OM_TARGET
    export OM_USERNAME
    export OM_PASSWORD

    # Test connection to Ops Manager
    if ! om $SKIP_SSL_VALIDATION curl -s -p /api/v0/info > /dev/null 2>&1; then
        log_error "Failed to connect to Ops Manager at ${OM_TARGET}"
        exit 1
    fi

    log_success "Connected to Ops Manager"

    log_info "Extracting BOSH Director credentials..."

    # Get BOSH environment details from Ops Manager
    local bosh_env
    bosh_env=$(om $SKIP_SSL_VALIDATION bosh-env --json)

    export BOSH_ENVIRONMENT=$(echo "$bosh_env" | jq -r '.BOSH_ENVIRONMENT // empty')
    export BOSH_CLIENT=$(echo "$bosh_env" | jq -r '.BOSH_CLIENT // empty')
    export BOSH_CLIENT_SECRET=$(echo "$bosh_env" | jq -r '.BOSH_CLIENT_SECRET // empty')
    export BOSH_CA_CERT=$(echo "$bosh_env" | jq -r '.BOSH_CA_CERT // empty')

    if [[ -z "$BOSH_ENVIRONMENT" || -z "$BOSH_CLIENT" ]]; then
        log_error "Failed to extract BOSH credentials from Ops Manager"
        exit 1
    fi

    # Write CA cert to temp file for BOSH CLI
    BOSH_CA_CERT_FILE=$(mktemp)
    echo "$BOSH_CA_CERT" > "$BOSH_CA_CERT_FILE"
    export BOSH_CA_CERT="$BOSH_CA_CERT_FILE"

    # Verify BOSH connection
    if ! bosh environment > /dev/null 2>&1; then
        log_error "Failed to connect to BOSH Director"
        rm -f "$BOSH_CA_CERT_FILE"
        exit 1
    fi

    log_success "Connected to BOSH Director at ${BOSH_ENVIRONMENT}"
}

#######################################
# Build and upload the authentik release
#######################################
upload_releases() {
    log_info "Uploading required BOSH releases..."

    # Upload BPM release
    log_info "Uploading BPM release..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would upload BPM release from bosh.io"
    else
        bosh upload-release https://bosh.io/d/github.com/cloudfoundry/bpm-release --name bpm || true
    fi

    # Upload PostgreSQL release (if using embedded postgres)
    if [[ "$USE_EXTERNAL_POSTGRES" != "true" ]]; then
        log_info "Uploading PostgreSQL release..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would upload PostgreSQL release from bosh.io"
        else
            bosh upload-release https://bosh.io/d/github.com/cloudfoundry/postgres-release --name postgres || true
        fi
    fi

    # Check if authentik release tarball exists, if not create it
    local release_tarball="${RELEASE_DIR}/authentik-release.tgz"

    if [[ ! -f "$release_tarball" ]]; then
        log_info "Authentik release tarball not found. Building release..."

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would build authentik release"
        else
            # Check if blobs are present
            if [[ ! -d "${RELEASE_DIR}/blobs/python" ]] || [[ ! -f "${RELEASE_DIR}/blobs/python/Python-3.12.4.tar.xz" ]]; then
                log_warning "Blobs not found. Running download-blobs.sh..."
                "${SCRIPT_DIR}/download-blobs.sh"

                log_warning "Please complete the manual steps outlined above and re-run this script."
                exit 1
            fi

            # Create the release
            cd "$RELEASE_DIR"
            bosh create-release --force --tarball="$release_tarball"
        fi
    fi

    # Upload authentik release
    log_info "Uploading Authentik release..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would upload authentik release from ${release_tarball}"
    else
        bosh upload-release "$release_tarball" || true
    fi

    log_success "All releases uploaded"
}

#######################################
# Upload required stemcell
#######################################
upload_stemcell() {
    log_info "Checking stemcell availability..."

    # Get the stemcell already used by Ops Manager deployments
    local stemcell_os="ubuntu-jammy"

    # Check if stemcell is already uploaded
    if bosh stemcells --json | jq -e '.Tables[0].Rows[] | select(.os == "ubuntu-jammy")' > /dev/null 2>&1; then
        log_success "Ubuntu Jammy stemcell already available"
        return
    fi

    log_info "Uploading Ubuntu Jammy stemcell..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would upload Ubuntu Jammy stemcell"
    else
        # Determine IaaS from Ops Manager
        local iaas
        iaas=$(om $SKIP_SSL_VALIDATION curl -s -p /api/v0/deployed/director/manifest | jq -r '.cloud_provider.type // "vsphere"')

        case "$iaas" in
            vsphere)
                bosh upload-stemcell "https://bosh.io/d/stemcells/bosh-vsphere-esxi-ubuntu-jammy-go_agent"
                ;;
            aws)
                bosh upload-stemcell "https://bosh.io/d/stemcells/bosh-aws-xen-hvm-ubuntu-jammy-go_agent"
                ;;
            azure)
                bosh upload-stemcell "https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-jammy-go_agent"
                ;;
            google)
                bosh upload-stemcell "https://bosh.io/d/stemcells/bosh-google-kvm-ubuntu-jammy-go_agent"
                ;;
            *)
                log_error "Unknown IaaS type: $iaas. Please upload stemcell manually."
                exit 1
                ;;
        esac
    fi

    log_success "Stemcell uploaded"
}

#######################################
# Generate deployment variables file
#######################################
generate_vars_file() {
    local vars_file="$1"

    log_info "Generating deployment variables..."

    cat > "$vars_file" << EOF
# Authentik Deployment Variables
# Generated by deploy-to-tanzu-ops-manager.sh

# SMTP Configuration
smtp_host: "${SMTP_HOST}"
smtp_port: ${SMTP_PORT}
smtp_from: "${SMTP_FROM}"
EOF

    if [[ "$USE_EXTERNAL_POSTGRES" == "true" ]]; then
        cat >> "$vars_file" << EOF

# External PostgreSQL Configuration
postgres_host: "${POSTGRES_HOST}"
postgres_port: ${POSTGRES_PORT}
postgres_user: "${POSTGRES_USER}"
postgres_password: "${POSTGRES_PASSWORD}"
postgres_database: "${POSTGRES_DATABASE}"
postgres_sslmode: "${POSTGRES_SSLMODE}"
EOF
    fi

    if [[ "$USE_S3_STORAGE" == "true" ]]; then
        cat >> "$vars_file" << EOF

# S3 Storage Configuration
s3_region: "${S3_REGION:-us-east-1}"
s3_endpoint: "${S3_ENDPOINT:-}"
s3_bucket_name: "${S3_BUCKET}"
s3_access_key: "${S3_ACCESS_KEY}"
s3_secret_key: "${S3_SECRET_KEY}"
EOF
    fi

    if [[ "$SCALE_INSTANCES" -gt 1 ]]; then
        cat >> "$vars_file" << EOF

# Scaling Configuration
authentik_instances: ${SCALE_INSTANCES}
EOF
    fi

    if [[ -n "${OUTPOST_TOKEN:-}" ]]; then
        cat >> "$vars_file" << EOF

# Outpost Configuration
outpost_token: "${OUTPOST_TOKEN}"
EOF
    fi

    log_success "Variables file generated: $vars_file"
}

#######################################
# Build operations file list
#######################################
build_ops_files() {
    local ops_files=()
    local ops_dir="${RELEASE_DIR}/operations"

    if [[ "$USE_EXTERNAL_POSTGRES" == "true" ]]; then
        ops_files+=("-o" "${ops_dir}/use-external-postgres.yml")
    fi

    if [[ "$USE_S3_STORAGE" == "true" ]]; then
        ops_files+=("-o" "${ops_dir}/use-s3-storage.yml")
    fi

    if [[ "$SCALE_INSTANCES" -gt 1 ]]; then
        ops_files+=("-o" "${ops_dir}/scale-authentik.yml")
    fi

    if [[ "$ADD_LDAP_OUTPOST" == "true" ]]; then
        ops_files+=("-o" "${ops_dir}/add-ldap-outpost.yml")
    fi

    if [[ "$ADD_RADIUS_OUTPOST" == "true" ]]; then
        ops_files+=("-o" "${ops_dir}/add-radius-outpost.yml")
    fi

    if [[ "$ADD_PROXY_OUTPOST" == "true" ]]; then
        ops_files+=("-o" "${ops_dir}/add-proxy-outpost.yml")
    fi

    echo "${ops_files[@]}"
}

#######################################
# Deploy authentik
#######################################
deploy_authentik() {
    log_info "Deploying Authentik..."

    local vars_file
    vars_file=$(mktemp --suffix=.yml)
    generate_vars_file "$vars_file"

    # Build ops files array
    local ops_files
    ops_files=$(build_ops_files)

    local manifest="${RELEASE_DIR}/manifests/authentik.yml"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "[DRY-RUN] Would deploy with the following command:"
        echo ""
        echo "bosh -d ${DEPLOYMENT_NAME} deploy ${manifest} \\"
        echo "    -l ${vars_file} \\"
        if [[ -n "$ops_files" ]]; then
            echo "    ${ops_files} \\"
        fi
        echo "    -n"
        echo ""
        echo "Variables file contents:"
        echo "========================"
        cat "$vars_file"
        echo ""
    else
        log_info "Running BOSH deployment..."

        # Run deployment
        # shellcheck disable=SC2086
        bosh -d "${DEPLOYMENT_NAME}" deploy "${manifest}" \
            -l "$vars_file" \
            ${ops_files} \
            -n

        log_success "Deployment completed successfully"
    fi

    rm -f "$vars_file"
}

#######################################
# Display deployment information
#######################################
show_deployment_info() {
    log_info "Retrieving deployment information..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would display deployment information"
        return
    fi

    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT INFORMATION          "
    echo "=========================================="
    echo ""

    # Get instances
    bosh -d "${DEPLOYMENT_NAME}" instances

    # Get authentik VM IP
    local authentik_ip
    authentik_ip=$(bosh -d "${DEPLOYMENT_NAME}" instances --json 2>/dev/null | \
        jq -r '.Tables[0].Rows[] | select(.instance | contains("authentik")) | .ips' | head -1)

    if [[ -n "$authentik_ip" ]]; then
        echo ""
        echo "=========================================="
        echo "           AUTHENTIK ACCESS              "
        echo "=========================================="
        echo ""
        echo "Authentik is available at:"
        echo "  HTTP:    http://${authentik_ip}:9000"
        echo "  HTTPS:   https://${authentik_ip}:9443"
        echo "  Metrics: http://${authentik_ip}:9300/metrics"
        echo ""
        echo "Initial Setup:"
        echo "  http://${authentik_ip}:9000/if/flow/initial-setup/"
        echo ""

        if [[ "$ADD_LDAP_OUTPOST" == "true" ]]; then
            echo "LDAP Outpost:"
            echo "  LDAP:  ldap://${authentik_ip}:3389"
            echo "  LDAPS: ldaps://${authentik_ip}:6636"
            echo ""
        fi

        if [[ "$ADD_RADIUS_OUTPOST" == "true" ]]; then
            echo "RADIUS Outpost:"
            echo "  UDP: ${authentik_ip}:1812"
            echo ""
        fi

        if [[ "$ADD_PROXY_OUTPOST" == "true" ]]; then
            echo "Proxy Outpost:"
            echo "  HTTP:  http://${authentik_ip}:9080"
            echo "  HTTPS: https://${authentik_ip}:9444"
            echo ""
        fi

        echo "=========================================="
        echo "              NEXT STEPS                 "
        echo "=========================================="
        echo ""
        echo "1. Access the initial setup URL above to create your admin account"
        echo "2. Configure your identity providers and applications"
        echo "3. Set up outpost tokens if using LDAP/RADIUS/Proxy outposts"
        echo ""

        if [[ -z "${OUTPOST_TOKEN:-}" ]] && \
           [[ "$ADD_LDAP_OUTPOST" == "true" || "$ADD_RADIUS_OUTPOST" == "true" || "$ADD_PROXY_OUTPOST" == "true" ]]; then
            log_warning "Outpost token was not provided during deployment."
            echo "To configure outposts:"
            echo "  1. Log into authentik admin UI"
            echo "  2. Go to Applications > Outposts"
            echo "  3. Create an outpost and copy the token"
            echo "  4. Re-run this script with --outpost-token <token>"
            echo ""
        fi
    fi
}

#######################################
# Cleanup function
#######################################
cleanup() {
    if [[ -n "${BOSH_CA_CERT_FILE:-}" ]] && [[ -f "${BOSH_CA_CERT_FILE}" ]]; then
        rm -f "$BOSH_CA_CERT_FILE"
    fi
}

#######################################
# Main function
#######################################
main() {
    echo ""
    echo "=========================================="
    echo "  Authentik Deployment to Tanzu Ops Mgr  "
    echo "=========================================="
    echo ""

    # Setup cleanup trap
    trap cleanup EXIT

    # Parse arguments
    parse_args "$@"

    # Check dependencies
    check_dependencies

    # Validate configuration
    validate_config

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi

    # Setup BOSH environment
    setup_bosh_environment

    # Upload releases
    upload_releases

    # Upload stemcell
    upload_stemcell

    # Deploy
    deploy_authentik

    # Show deployment info
    show_deployment_info

    log_success "Deployment complete!"
}

# Run main function
main "$@"
