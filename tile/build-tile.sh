#!/bin/bash
#
# Build Authentik Tile for Tanzu Operations Manager
#
# This script packages the Authentik BOSH release into a .pivotal tile
# that can be imported into Tanzu Operations Manager.
#
# Prerequisites:
#   - BOSH CLI installed
#   - wget or curl installed
#   - zip installed
#   - Blobs downloaded (run scripts/download-blobs.sh first)
#
# Usage:
#   ./build-tile.sh [options]
#
# Options:
#   --version VERSION      Tile version (default: 2025.12.1)
#   --output-dir DIR       Output directory for the tile (default: ./output)
#   --skip-release-build   Skip building the BOSH release (use existing tarball)
#   --skip-dependency-download  Skip downloading BPM and Postgres releases
#   --help                 Show this help message
#
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
TILE_VERSION="2025.12.1"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SKIP_RELEASE_BUILD=false
SKIP_DEPENDENCY_DOWNLOAD=false

# Dependency versions
BPM_VERSION="1.2.20"
POSTGRES_VERSION="53"
STEMCELL_VERSION="1.406"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                TILE_VERSION="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --skip-release-build)
                SKIP_RELEASE_BUILD=true
                shift
                ;;
            --skip-dependency-download)
                SKIP_DEPENDENCY_DOWNLOAD=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v bosh &> /dev/null; then
        missing_deps+=("bosh")
    fi

    if ! command -v zip &> /dev/null; then
        missing_deps+=("zip")
    fi

    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        missing_deps+=("wget or curl")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi

    log_success "All dependencies present"
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v wget &> /dev/null; then
        wget -q -O "$output" "$url"
    else
        curl -sL -o "$output" "$url"
    fi
}

setup_build_directory() {
    log_info "Setting up build directory..."

    # Create output and build directories
    mkdir -p "${OUTPUT_DIR}"

    # Create tile structure
    BUILD_DIR=$(mktemp -d)
    TILE_DIR="${BUILD_DIR}/tile"
    mkdir -p "${TILE_DIR}/metadata"
    mkdir -p "${TILE_DIR}/releases"
    mkdir -p "${TILE_DIR}/migrations/v1"
    mkdir -p "${TILE_DIR}/content_migrations"

    log_success "Build directory: ${BUILD_DIR}"
}

download_dependencies() {
    if [[ "$SKIP_DEPENDENCY_DOWNLOAD" == "true" ]]; then
        log_info "Skipping dependency download..."
        return
    fi

    log_info "Downloading dependency releases..."

    # Download BPM release
    local bpm_file="${TILE_DIR}/releases/bpm-${BPM_VERSION}.tgz"
    if [[ ! -f "$bpm_file" ]]; then
        log_info "Downloading BPM release v${BPM_VERSION}..."
        download_file \
            "https://bosh.io/d/github.com/cloudfoundry/bpm-release?v=${BPM_VERSION}" \
            "$bpm_file"
    fi

    # Download PostgreSQL release
    local postgres_file="${TILE_DIR}/releases/postgres-${POSTGRES_VERSION}.tgz"
    if [[ ! -f "$postgres_file" ]]; then
        log_info "Downloading PostgreSQL release v${POSTGRES_VERSION}..."
        download_file \
            "https://bosh.io/d/github.com/cloudfoundry/postgres-release?v=${POSTGRES_VERSION}" \
            "$postgres_file"
    fi

    log_success "Dependencies downloaded"
}

build_authentik_release() {
    if [[ "$SKIP_RELEASE_BUILD" == "true" ]]; then
        log_info "Skipping release build, looking for existing tarball..."

        # Look for existing release tarball
        local existing_release
        existing_release=$(find "${RELEASE_DIR}" -maxdepth 1 -name "authentik-*.tgz" -o -name "authentik-release.tgz" | head -1)

        if [[ -n "$existing_release" ]]; then
            cp "$existing_release" "${TILE_DIR}/releases/authentik-${TILE_VERSION}.tgz"
            log_success "Using existing release: $existing_release"
            return
        else
            log_warning "No existing release found, building..."
        fi
    fi

    log_info "Building Authentik BOSH release..."

    # Check if blobs are present
    if [[ ! -f "${RELEASE_DIR}/blobs/python/Python-3.12.4.tar.xz" ]]; then
        log_error "Blobs not found. Please run scripts/download-blobs.sh first"
        exit 1
    fi

    cd "${RELEASE_DIR}"

    # Create the release
    bosh create-release \
        --force \
        --version="${TILE_VERSION}" \
        --tarball="${TILE_DIR}/releases/authentik-${TILE_VERSION}.tgz"

    log_success "Authentik release built"
}

generate_metadata() {
    log_info "Generating tile metadata..."

    # Copy metadata template
    cp "${SCRIPT_DIR}/metadata/metadata.yml" "${TILE_DIR}/metadata/"

    # Update version in metadata
    sed -i "s/^product_version:.*/product_version: \"${TILE_VERSION}\"/" \
        "${TILE_DIR}/metadata/metadata.yml"

    # Update release versions
    sed -i "s/version: \"2025.12.1\"/version: \"${TILE_VERSION}\"/" \
        "${TILE_DIR}/metadata/metadata.yml"
    sed -i "s/file: authentik-2025.12.1.tgz/file: authentik-${TILE_VERSION}.tgz/" \
        "${TILE_DIR}/metadata/metadata.yml"

    # Generate icon placeholder (base64 encoded 1x1 transparent PNG)
    local icon_base64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    # Replace icon placeholder
    sed -i "s|((icon_image))|${icon_base64}|" "${TILE_DIR}/metadata/metadata.yml"

    log_success "Metadata generated"
}

create_migrations() {
    log_info "Creating migration files..."

    # Create initial migration (v1)
    cat > "${TILE_DIR}/migrations/v1/202501301200_initial.js" << 'EOF'
exports.migrate = function(input) {
  // Initial migration - no changes needed
  return input;
};
EOF

    # Create content migration for future upgrades
    cat > "${TILE_DIR}/content_migrations/content_migrations.yml" << EOF
---
product: authentik
installation_schema_version: "1.0"
EOF

    log_success "Migrations created"
}

package_tile() {
    log_info "Packaging tile..."

    local tile_name="authentik-${TILE_VERSION}.pivotal"
    local tile_path="${OUTPUT_DIR}/${tile_name}"

    cd "${TILE_DIR}"
    zip -r "${tile_path}" .

    log_success "Tile packaged: ${tile_path}"
}

cleanup() {
    if [[ -n "${BUILD_DIR:-}" ]] && [[ -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
    fi
}

show_summary() {
    echo ""
    echo "=========================================="
    echo "         TILE BUILD COMPLETE             "
    echo "=========================================="
    echo ""
    echo "Tile: ${OUTPUT_DIR}/authentik-${TILE_VERSION}.pivotal"
    echo ""
    echo "To install the tile:"
    echo "  1. Log into Tanzu Operations Manager"
    echo "  2. Click 'Import a Product'"
    echo "  3. Select the .pivotal file"
    echo "  4. Click '+' to stage the product"
    echo "  5. Configure the tile settings"
    echo "  6. Apply Changes"
    echo ""
    echo "Or use the OM CLI:"
    echo "  om upload-product -p ${OUTPUT_DIR}/authentik-${TILE_VERSION}.pivotal"
    echo "  om stage-product -p authentik -v ${TILE_VERSION}"
    echo "  om configure-product -c config.yml"
    echo "  om apply-changes"
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo "      Authentik Tile Builder             "
    echo "=========================================="
    echo ""

    trap cleanup EXIT

    parse_args "$@"
    check_dependencies
    setup_build_directory
    download_dependencies
    build_authentik_release
    generate_metadata
    create_migrations
    package_tile
    show_summary
}

main "$@"
