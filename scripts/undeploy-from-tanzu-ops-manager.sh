#!/bin/bash
#
# Remove Authentik BOSH Deployment from Tanzu Operations Manager
#
# This script removes the Authentik deployment from the BOSH Director
# managed by Tanzu Operations Manager.
#
# Usage:
#   ./undeploy-from-tanzu-ops-manager.sh [options]
#
# Options:
#   --ops-manager-url       Ops Manager URL (or set OM_TARGET)
#   --ops-manager-username  Ops Manager username (or set OM_USERNAME)
#   --ops-manager-password  Ops Manager password (or set OM_PASSWORD)
#   --skip-ssl-validation   Skip SSL certificate validation
#   --deployment-name       BOSH deployment name (default: authentik)
#   --force                 Skip confirmation prompt
#   --cleanup-releases      Also remove uploaded releases
#   --help                  Show this help message
#
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEPLOYMENT_NAME="authentik"
SKIP_SSL_VALIDATION=""
FORCE=false
CLEANUP_RELEASES=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

show_help() {
    head -25 "$0" | grep -E "^#" | tail -n +3 | sed 's/^# \?//'
    exit 0
}

check_dependencies() {
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
        exit 1
    fi
}

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
            --force)
                FORCE=true
                shift
                ;;
            --cleanup-releases)
                CLEANUP_RELEASES=true
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

validate_config() {
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
}

setup_bosh_environment() {
    log_info "Connecting to Tanzu Operations Manager..."

    export OM_TARGET
    export OM_USERNAME
    export OM_PASSWORD

    if ! om $SKIP_SSL_VALIDATION curl -s -p /api/v0/info > /dev/null 2>&1; then
        log_error "Failed to connect to Ops Manager at ${OM_TARGET}"
        exit 1
    fi

    log_info "Extracting BOSH Director credentials..."

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

    BOSH_CA_CERT_FILE=$(mktemp)
    echo "$BOSH_CA_CERT" > "$BOSH_CA_CERT_FILE"
    export BOSH_CA_CERT="$BOSH_CA_CERT_FILE"

    if ! bosh environment > /dev/null 2>&1; then
        log_error "Failed to connect to BOSH Director"
        rm -f "$BOSH_CA_CERT_FILE"
        exit 1
    fi

    log_success "Connected to BOSH Director"
}

confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "You are about to delete the '${DEPLOYMENT_NAME}' deployment."
    echo ""
    echo "This will:"
    echo "  - Stop all running Authentik services"
    echo "  - Delete all VMs associated with this deployment"
    echo "  - Remove persistent disks (DATA LOSS)"
    echo ""

    read -p "Are you sure you want to continue? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss])
            return 0
            ;;
        *)
            log_info "Deletion cancelled."
            exit 0
            ;;
    esac
}

delete_deployment() {
    log_info "Deleting deployment '${DEPLOYMENT_NAME}'..."

    # Check if deployment exists
    if ! bosh -d "${DEPLOYMENT_NAME}" deployment > /dev/null 2>&1; then
        log_warning "Deployment '${DEPLOYMENT_NAME}' not found"
        return 0
    fi

    bosh -d "${DEPLOYMENT_NAME}" delete-deployment -n

    log_success "Deployment deleted successfully"
}

cleanup_releases() {
    if [[ "$CLEANUP_RELEASES" != "true" ]]; then
        return 0
    fi

    log_info "Cleaning up uploaded releases..."

    # Delete authentik release (if no other deployments use it)
    if bosh releases --json | jq -e '.Tables[0].Rows[] | select(.name == "authentik")' > /dev/null 2>&1; then
        log_info "Removing authentik release..."
        bosh delete-release authentik -n || true
    fi

    log_success "Release cleanup complete"
}

cleanup() {
    if [[ -n "${BOSH_CA_CERT_FILE:-}" ]] && [[ -f "${BOSH_CA_CERT_FILE}" ]]; then
        rm -f "$BOSH_CA_CERT_FILE"
    fi
}

main() {
    echo ""
    echo "=========================================="
    echo "  Remove Authentik from Tanzu Ops Mgr    "
    echo "=========================================="
    echo ""

    trap cleanup EXIT

    parse_args "$@"
    check_dependencies
    validate_config
    setup_bosh_environment
    confirm_deletion
    delete_deployment
    cleanup_releases

    log_success "Undeployment complete!"
}

main "$@"
