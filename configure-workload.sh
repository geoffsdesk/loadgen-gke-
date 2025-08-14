#!/bin/bash

# Workload Configuration Script
# This script allows you to configure different workload types and parameters

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# Function to show current configuration
show_current_config() {
    print_status "Current workload configuration:"
    echo
    kubectl get configmap loadgen-config -n loadgen -o yaml
    echo
}

# Function to configure workload type
configure_workload_type() {
    echo "Available workload types:"
    echo "1. cpu - CPU-intensive workload"
    echo "2. memory - Memory-intensive workload"
    echo "3. network - Network-intensive workload"
    echo "4. storage - Storage-intensive workload"
    echo "5. mixed - Combined workload (default)"
    echo
    read -p "Select workload type (1-5): " WORKLOAD_CHOICE
    
    case $WORKLOAD_CHOICE in
        1) WORKLOAD_TYPE="cpu" ;;
        2) WORKLOAD_TYPE="memory" ;;
        3) WORKLOAD_TYPE="network" ;;
        4) WORKLOAD_TYPE="storage" ;;
        5) WORKLOAD_TYPE="mixed" ;;
        *) echo "Invalid choice, using mixed"; WORKLOAD_TYPE="mixed" ;;
    esac
    
    kubectl patch configmap loadgen-config -n loadgen --type='merge' -p="{\"data\":{\"workload-type\":\"$WORKLOAD_TYPE\"}}"
    print_success "Workload type set to: $WORKLOAD_TYPE"
}

# Function to configure load intensity
configure_intensity() {
    echo "Available intensity levels:"
    echo "1. low - Light load (20% CPU, 100MB RAM)"
    echo "2. medium - Moderate load (50% CPU, 250MB RAM) - default"
    echo "3. high - Heavy load (80% CPU, 500MB RAM)"
    echo "4. custom - Custom parameters"
    echo
    read -p "Select intensity level (1-4): " INTENSITY_CHOICE
    
    case $INTENSITY_CHOICE in
        1) INTENSITY="low" ;;
        2) INTENSITY="medium" ;;
        3) INTENSITY="high" ;;
        4) INTENSITY="custom" ;;
        *) echo "Invalid choice, using medium"; INTENSITY="medium" ;;
    esac
    
    kubectl patch configmap loadgen-config -n loadgen --type='merge' -p="{\"data\":{\"load-intensity\":\"$INTENSITY\"}}"
    print_success "Load intensity set to: $INTENSITY"
}

# Function to configure custom parameters
configure_custom_params() {
    print_status "Configuring custom parameters..."
    
    read -p "CPU threads (default: 4): " CPU_THREADS
    CPU_THREADS=${CPU_THREADS:-4}
    
    read -p "Memory chunk size in MB (default: 250): " MEMORY_CHUNK_SIZE
    MEMORY_CHUNK_SIZE=${MEMORY_CHUNK_SIZE:-250}
    
    read -p "Network concurrent requests (default: 3): " NETWORK_REQUESTS
    NETWORK_REQUESTS=${NETWORK_REQUESTS:-3}
    
    read -p "Storage file size in MB (default: 1): " STORAGE_FILE_SIZE
    STORAGE_FILE_SIZE=${STORAGE_FILE_SIZE:-1}
    
    # Update configmap
    kubectl patch configmap loadgen-config -n loadgen --type='merge' -p="{\"data\":{\"cpu-threads\":\"$CPU_THREADS\",\"memory-chunk-size-mb\":\"$MEMORY_CHUNK_SIZE\",\"network-concurrent-requests\":\"$NETWORK_REQUESTS\",\"storage-file-size-mb\":\"$STORAGE_FILE_SIZE\"}}"
    
    print_success "Custom parameters configured"
}

# Function to configure test duration
configure_duration() {
    read -p "Enter test duration in seconds (default: 300): " DURATION
    DURATION=${DURATION:-300}
    
    kubectl patch configmap loadgen-config -n loadgen --type='merge' -p="{\"data\":{\"duration\":\"$DURATION\"}}"
    print_success "Test duration set to: ${DURATION}s"
}

# Function to enable/disable burst pattern
configure_burst_pattern() {
    read -p "Enable burst pattern? (y/n, default: n): " BURST_CHOICE
    BURST_CHOICE=${BURST_CHOICE:-n}
    
    if [[ "$BURST_CHOICE" =~ ^[Yy]$ ]]; then
        BURST_PATTERN="true"
    else
        BURST_PATTERN="false"
    fi
    
    kubectl patch configmap loadgen-config -n loadgen --type='merge' -p="{\"data\":{\"burst-pattern\":\"$BURST_PATTERN\"}}"
    print_success "Burst pattern: $BURST_PATTERN"
}

# Function to restart load generator
restart_loadgen() {
    print_status "Restarting load generator with new configuration..."
    kubectl rollout restart deployment/loadgen -n loadgen
    
    print_status "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/loadgen -n loadgen
    
    print_success "Load generator restarted with new configuration"
}

# Function to show main menu
show_menu() {
    echo
    echo "=========================================="
    echo "    Workload Configuration Menu"
    echo "=========================================="
    echo "1. Show current configuration"
    echo "2. Configure workload type"
    echo "3. Configure load intensity"
    echo "4. Configure custom parameters"
    echo "5. Configure test duration"
    echo "6. Configure burst pattern"
    echo "7. Restart load generator"
    echo "8. Exit"
    echo
    read -p "Select option (1-8): " MENU_CHOICE
    
    case $MENU_CHOICE in
        1) show_current_config ;;
        2) configure_workload_type ;;
        3) configure_intensity ;;
        4) configure_custom_params ;;
        5) configure_duration ;;
        6) configure_burst_pattern ;;
        7) restart_loadgen ;;
        8) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice"; show_menu ;;
    esac
}

# Main execution
main() {
    echo "=========================================="
    echo "    GKE Load Generator Configuration"
    echo "=========================================="
    echo
    
    # Check if loadgen namespace exists
    if ! kubectl get namespace loadgen &> /dev/null; then
        print_warning "Load generator namespace not found. Please run deploy.sh first."
        exit 1
    fi
    
    # Check if configmap exists
    if ! kubectl get configmap loadgen-config -n loadgen &> /dev/null; then
        print_warning "Load generator configmap not found. Please run deploy.sh first."
        exit 1
    fi
    
    print_success "Connected to loadgen namespace"
    
    # Show menu loop
    while true; do
        show_menu
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
