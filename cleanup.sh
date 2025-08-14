#!/bin/bash

# GKE Load Generator Cleanup Script
# This script removes all deployed resources from your GKE cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo "=========================================="
    echo "    GKE Load Generator Cleanup"
    echo "=========================================="
    echo
    print_warning "This will remove ALL load generator and monitoring resources from your cluster!"
    echo
    echo "Resources to be removed:"
    echo "- loadgen namespace and all resources"
    echo "- monitoring namespace and all resources"
    echo "- Load generator deployment"
    echo "- Grafana deployment"
    echo "- All associated services, configmaps, and PVCs"
    echo
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
}

# Function to check if namespaces exist
check_namespaces() {
    LOADGEN_EXISTS=false
    MONITORING_EXISTS=false
    
    if kubectl get namespace loadgen &> /dev/null; then
        LOADGEN_EXISTS=true
    fi
    
    if kubectl get namespace monitoring &> /dev/null; then
        MONITORING_EXISTS=true
    fi
    
    if [ "$LOADGEN_EXISTS" = false ] && [ "$MONITORING_EXISTS" = false ]; then
        print_warning "No loadgen or monitoring namespaces found. Nothing to clean up."
        exit 0
    fi
}

# Function to cleanup loadgen namespace
cleanup_loadgen() {
    if [ "$LOADGEN_EXISTS" = true ]; then
        print_status "Cleaning up loadgen namespace..."
        
        # Delete all resources in loadgen namespace
        kubectl delete all --all -n loadgen --ignore-not-found=true
        kubectl delete configmap --all -n loadgen --ignore-not-found=true
        kubectl delete namespace loadgen --ignore-not-found=true
        
        print_success "loadgen namespace cleaned up"
    fi
}

# Function to cleanup monitoring namespace
cleanup_monitoring() {
    if [ "$MONITORING_EXISTS" = true ]; then
        print_status "Cleaning up monitoring namespace..."
        
        # Delete all resources in monitoring namespace
        kubectl delete all --all -n monitoring --ignore-not-found=true
        kubectl delete configmap --all -n monitoring --ignore-not-found=true
        kubectl delete pvc --all -n monitoring --ignore-not-found=true
        kubectl delete namespace monitoring --ignore-not-found=true
        
        print_success "monitoring namespace cleaned up"
    fi
}

# Function to cleanup Docker images (optional)
cleanup_docker_images() {
    echo
    read -p "Would you like to remove Docker images as well? (y/n): " CLEANUP_DOCKER
    
    if [[ "$CLEANUP_DOCKER" =~ ^[Yy]$ ]]; then
        print_status "Cleaning up Docker images..."
        
        # Remove local images
        docker rmi loadgen:latest 2>/dev/null || true
        docker rmi gcr.io/*/loadgen:latest 2>/dev/null || true
        
        print_success "Docker images cleaned up"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    print_success "Cleanup completed successfully!"
    echo
    echo "Removed resources:"
    if [ "$LOADGEN_EXISTS" = true ]; then
        echo "✓ loadgen namespace and all resources"
    fi
    if [ "$MONITORING_EXISTS" = true ]; then
        echo "✓ monitoring namespace and all resources"
    fi
    echo
    echo "Your GKE cluster is now clean of load generator resources."
}

# Main execution
main() {
    confirm_cleanup
    check_namespaces
    cleanup_loadgen
    cleanup_monitoring
    cleanup_docker_images
    show_cleanup_summary
}

# Run main function
main "$@"
