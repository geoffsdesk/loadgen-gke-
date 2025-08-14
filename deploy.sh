#!/bin/bash

# GKE Load Generator Deployment Script
# This script deploys the load generator and monitoring stack to your GKE cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=""
CLUSTER_NAME=""
CLUSTER_ZONE=""
CLUSTER_REGION=""
ENABLE_GMP="false"

# Function to print colored output
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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to get GKE cluster information
get_cluster_info() {
    print_status "Getting GKE cluster information..."
    
    # Get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        print_error "No GCP project configured. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    print_status "Current project: $PROJECT_ID"
    
    # List available clusters
    print_status "Available GKE clusters:"
    gcloud container clusters list --project="$PROJECT_ID" --format="table(name,location,status)"
    
    # Get cluster name
    if [ -z "$CLUSTER_NAME" ]; then
        echo
        read -p "Enter the name of your GKE cluster: " CLUSTER_NAME
    fi
    
    # Get cluster location
    CLUSTER_INFO=$(gcloud container clusters describe "$CLUSTER_NAME" --project="$PROJECT_ID" --format="value(location,zone)" 2>/dev/null)
    if [ -n "$CLUSTER_INFO" ]; then
        if [[ "$CLUSTER_INFO" == *"/"* ]]; then
            CLUSTER_REGION=$(echo "$CLUSTER_INFO" | cut -d'/' -f2)
        else
            CLUSTER_ZONE="$CLUSTER_INFO"
        fi
    fi
    
    if [ -z "$CLUSTER_ZONE" ] && [ -z "$CLUSTER_REGION" ]; then
        echo
        read -p "Enter the zone/region of your cluster (e.g., us-central1-a or us-central1): " CLUSTER_LOCATION
        if [[ "$CLUSTER_LOCATION" == *"-"* ]]; then
            CLUSTER_ZONE="$CLUSTER_LOCATION"
        else
            CLUSTER_REGION="$CLUSTER_LOCATION"
        fi
    fi
    
    print_success "Cluster: $CLUSTER_NAME in $CLUSTER_ZONE$CLUSTER_REGION"
}

# Function to configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl for cluster $CLUSTER_NAME..."
    
    if [ -n "$CLUSTER_ZONE" ]; then
        gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" --project="$PROJECT_ID"
    else
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$CLUSTER_REGION" --project="$PROJECT_ID"
    fi
    
    print_success "kubectl configured for cluster $CLUSTER_NAME"
}

# Function to check GMP status
check_gmp_status() {
    print_status "Checking Google Managed Prometheus status..."
    
    if [ -n "$CLUSTER_ZONE" ]; then
        GMP_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" --project="$PROJECT_ID" --format="value(monitoringConfig.managedPrometheusConfig.enabled)" 2>/dev/null)
    else
        GMP_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --region="$CLUSTER_REGION" --project="$PROJECT_ID" --format="value(monitoringConfig.managedPrometheusConfig.enabled)" 2>/dev/null)
    fi
    
    if [ "$GMP_STATUS" = "True" ]; then
        print_success "Google Managed Prometheus is enabled on this cluster"
        ENABLE_GMP="true"
    else
        print_warning "Google Managed Prometheus is not enabled on this cluster"
        echo
        read -p "Would you like to enable GMP? (y/n): " ENABLE_GMP_CHOICE
        if [[ "$ENABLE_GMP_CHOICE" =~ ^[Yy]$ ]]; then
            enable_gmp
        fi
    fi
}

# Function to enable GMP
enable_gmp() {
    print_status "Enabling Google Managed Prometheus..."
    
    if [ -n "$CLUSTER_ZONE" ]; then
        gcloud container clusters update "$CLUSTER_NAME" \
            --zone="$CLUSTER_ZONE" \
            --project="$PROJECT_ID" \
            --enable-managed-prometheus
    else
        gcloud container clusters update "$CLUSTER_NAME" \
            --region="$CLUSTER_REGION" \
            --project="$PROJECT_ID" \
            --enable-managed-prometheus
    fi
    
    ENABLE_GMP="true"
    print_success "Google Managed Prometheus enabled"
}

# Function to build and push Docker image
build_image() {
    print_status "Building Docker image..."
    
    # Build the image
    docker build -t loadgen:latest .
    
    # Tag for GCR/Artifact Registry
    docker tag loadgen:latest gcr.io/$PROJECT_ID/loadgen:latest
    
    # Push to registry
    print_status "Pushing image to GCR..."
    docker push gcr.io/$PROJECT_ID/loadgen:latest
    
    print_success "Docker image built and pushed"
}

# Function to deploy to Kubernetes
deploy_to_k8s() {
    print_status "Deploying to Kubernetes..."
    
    # Create namespaces
    kubectl apply -f k8s/namespace.yaml
    
    # Deploy load generator
    kubectl apply -f k8s/configmap.yaml
    kubectl apply -f k8s/deployment.yaml
    
    # Update image in deployment
    kubectl set image deployment/loadgen loadgen=gcr.io/$PROJECT_ID/loadgen:latest -n loadgen
    
    # Deploy Grafana
    kubectl apply -f k8s/grafana-deployment.yaml
    kubectl apply -f k8s/grafana-datasources.yaml
    kubectl apply -f k8s/grafana-dashboards.yaml
    
    print_success "Kubernetes deployment completed"
}

# Function to wait for deployment
wait_for_deployment() {
    print_status "Waiting for deployments to be ready..."
    
    # Wait for load generator
    kubectl wait --for=condition=available --timeout=300s deployment/loadgen -n loadgen
    
    # Wait for Grafana
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring
    
    print_success "All deployments are ready"
}

# Function to display access information
show_access_info() {
    print_success "Deployment completed successfully!"
    echo
    echo "Access Information:"
    echo "=================="
    echo
    echo "Load Generator Metrics:"
    echo "  kubectl port-forward svc/loadgen-service 8000:8000 -n loadgen"
    echo "  http://localhost:8000/metrics"
    echo
    echo "Grafana Dashboard:"
    echo "  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "  http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo
    echo "View Load Generator Logs:"
    echo "  kubectl logs -f deployment/loadgen -n loadgen"
    echo
    echo "View Grafana Logs:"
    echo "  kubectl logs -f deployment/grafana -n monitoring"
    echo
    echo "Cluster Status:"
    echo "  kubectl get pods -n loadgen"
    echo "  kubectl get pods -n monitoring"
}

# Function to run load test
run_load_test() {
    echo
    read -p "Would you like to run a load test now? (y/n): " RUN_TEST
    if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
        print_status "Running load test..."
        
        # Get current workload configuration
        WORKLOAD_TYPE=$(kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.workload-type}')
        INTENSITY=$(kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.load-intensity}')
        DURATION=$(kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.duration}')
        
        print_status "Current configuration: Workload=$WORKLOAD_TYPE, Intensity=$INTENSITY, Duration=${DURATION}s"
        
        # Restart deployment to trigger new load test
        kubectl rollout restart deployment/loadgen -n loadgen
        
        print_success "Load test started. Check Grafana dashboard for metrics."
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "    GKE Load Generator Deployment"
    echo "=========================================="
    echo
    
    check_prerequisites
    get_cluster_info
    configure_kubectl
    check_gmp_status
    build_image
    deploy_to_k8s
    wait_for_deployment
    show_access_info
    run_load_test
    
    echo
    print_success "Setup complete! Your load generator is now running on GKE."
}

# Run main function
main "$@"
