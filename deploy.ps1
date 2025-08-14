# GKE Load Generator Deployment Script (PowerShell)
# This script deploys the load generator and monitoring stack to your GKE cluster

param(
    [string]$ClusterName = "",
    [string]$ClusterZone = "",
    [string]$ClusterRegion = "",
    [switch]$EnableGMP
)

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    # Check if gcloud is installed
    try {
        $null = Get-Command gcloud -ErrorAction Stop
    }
    catch {
        Write-Error "gcloud CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if kubectl is installed
    try {
        $null = Get-Command kubectl -ErrorAction Stop
    }
    catch {
        Write-Error "kubectl is not installed. Please install it first."
        exit 1
    }
    
    # Check if docker is installed
    try {
        $null = Get-Command docker -ErrorAction Stop
    }
    catch {
        Write-Error "Docker is not installed. Please install it first."
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

# Function to get GKE cluster information
function Get-ClusterInfo {
    Write-Status "Getting GKE cluster information..."
    
    # Get current project
    $ProjectId = gcloud config get-value project 2>$null
    if (-not $ProjectId) {
        Write-Error "No GCP project configured. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    }
    
    Write-Status "Current project: $ProjectId"
    
    # List available clusters
    Write-Status "Available GKE clusters:"
    gcloud container clusters list --project="$ProjectId" --format="table(name,location,status)"
    
    # Get cluster name
    if (-not $ClusterName) {
        $ClusterName = Read-Host "Enter the name of your GKE cluster"
    }
    
    # Get cluster location
    try {
        if ($ClusterZone) {
            $ClusterInfo = gcloud container clusters describe "$ClusterName" --zone="$ClusterZone" --project="$ProjectId" --format="value(location,zone)" 2>$null
        }
        elseif ($ClusterRegion) {
            $ClusterInfo = gcloud container clusters describe "$ClusterName" --region="$ClusterRegion" --project="$ProjectId" --format="value(location,zone)" 2>$null
        }
        else {
            $ClusterInfo = gcloud container clusters describe "$ClusterName" --project="$ProjectId" --format="value(location,zone)" 2>$null
        }
        
        if ($ClusterInfo -and $ClusterInfo.Contains("/")) {
            $ClusterRegion = $ClusterInfo.Split("/")[1]
        }
        elseif ($ClusterInfo) {
            $ClusterZone = $ClusterInfo
        }
    }
    catch {
        # Cluster info not found, will prompt user
    }
    
    if (-not $ClusterZone -and -not $ClusterRegion) {
        $ClusterLocation = Read-Host "Enter the zone/region of your cluster (e.g., us-central1-a or us-central1)"
        if ($ClusterLocation.Contains("-")) {
            $ClusterZone = $ClusterLocation
        }
        else {
            $ClusterRegion = $ClusterLocation
        }
    }
    
    Write-Success "Cluster: $ClusterName in $ClusterZone$ClusterRegion"
    
    return @{
        ProjectId = $ProjectId
        ClusterName = $ClusterName
        ClusterZone = $ClusterZone
        ClusterRegion = $ClusterRegion
    }
}

# Function to configure kubectl
function Set-KubectlConfig {
    param($ClusterInfo)
    
    Write-Status "Configuring kubectl for cluster $($ClusterInfo.ClusterName)..."
    
    if ($ClusterInfo.ClusterZone) {
        gcloud container clusters get-credentials "$($ClusterInfo.ClusterName)" --zone="$($ClusterInfo.ClusterZone)" --project="$($ClusterInfo.ProjectId)"
    }
    else {
        gcloud container clusters get-credentials "$($ClusterInfo.ClusterName)" --region="$($ClusterInfo.ClusterRegion)" --project="$($ClusterInfo.ProjectId)"
    }
    
    Write-Success "kubectl configured for cluster $($ClusterInfo.ClusterName)"
}

# Function to check GMP status
function Test-GMPStatus {
    param($ClusterInfo)
    
    Write-Status "Checking Google Managed Prometheus status..."
    
    try {
        if ($ClusterInfo.ClusterZone) {
            $GMPStatus = gcloud container clusters describe "$($ClusterInfo.ClusterName)" --zone="$($ClusterInfo.ClusterZone)" --project="$($ClusterInfo.ProjectId)" --format="value(monitoringConfig.managedPrometheusConfig.enabled)" 2>$null
        }
        else {
            $GMPStatus = gcloud container clusters describe "$($ClusterInfo.ClusterName)" --region="$($ClusterInfo.ClusterRegion)" --project="$($ClusterInfo.ProjectId)" --format="value(monitoringConfig.managedPrometheusConfig.enabled)" 2>$null
        }
        
        if ($GMPStatus -eq "True") {
            Write-Success "Google Managed Prometheus is enabled on this cluster"
            return $true
        }
        else {
            Write-Warning "Google Managed Prometheus is not enabled on this cluster"
            $EnableGMPChoice = Read-Host "Would you like to enable GMP? (y/n)"
            if ($EnableGMPChoice -match "^[Yy]$") {
                Enable-GMP -ClusterInfo $ClusterInfo
                return $true
            }
            return $false
        }
    }
    catch {
        Write-Warning "Could not determine GMP status"
        return $false
    }
}

# Function to enable GMP
function Enable-GMP {
    param($ClusterInfo)
    
    Write-Status "Enabling Google Managed Prometheus..."
    
    if ($ClusterInfo.ClusterZone) {
        gcloud container clusters update "$($ClusterInfo.ClusterName)" --zone="$($ClusterInfo.ClusterZone)" --project="$($ClusterInfo.ProjectId)" --enable-managed-prometheus
    }
    else {
        gcloud container clusters update "$($ClusterInfo.ClusterName)" --region="$($ClusterInfo.ClusterRegion)" --project="$($ClusterInfo.ProjectId)" --enable-managed-prometheus
    }
    
    Write-Success "Google Managed Prometheus enabled"
}

# Function to build and push Docker image
function Build-Image {
    param($ClusterInfo)
    
    Write-Status "Building Docker image..."
    
    # Build the image
    docker build -t loadgen:latest .
    
    # Tag for GCR/Artifact Registry
    docker tag loadgen:latest "gcr.io/$($ClusterInfo.ProjectId)/loadgen:latest"
    
    # Push to registry
    Write-Status "Pushing image to GCR..."
    docker push "gcr.io/$($ClusterInfo.ProjectId)/loadgen:latest"
    
    Write-Success "Docker image built and pushed"
}

# Function to deploy to Kubernetes
function Deploy-Kubernetes {
    param($ClusterInfo)
    
    Write-Status "Deploying to Kubernetes..."
    
    # Create namespaces
    kubectl apply -f k8s/namespace.yaml
    
    # Deploy load generator
    kubectl apply -f k8s/configmap.yaml
    kubectl apply -f k8s/deployment.yaml
    
    # Update image in deployment
    kubectl set image deployment/loadgen loadgen="gcr.io/$($ClusterInfo.ProjectId)/loadgen:latest" -n loadgen
    
    # Deploy Grafana
    kubectl apply -f k8s/grafana-deployment.yaml
    kubectl apply -f k8s/grafana-datasources.yaml
    kubectl apply -f k8s/grafana-dashboards.yaml
    
    Write-Success "Kubernetes deployment completed"
}

# Function to wait for deployment
function Wait-Deployment {
    Write-Status "Waiting for deployments to be ready..."
    
    # Wait for load generator
    kubectl wait --for=condition=available --timeout=300s deployment/loadgen -n loadgen
    
    # Wait for Grafana
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring
    
    Write-Success "All deployments are ready"
}

# Function to display access information
function Show-AccessInfo {
    Write-Success "Deployment completed successfully!"
    Write-Host ""
    Write-Host "Access Information:"
    Write-Host "=================="
    Write-Host ""
    Write-Host "Load Generator Metrics:"
    Write-Host "  kubectl port-forward svc/loadgen-service 8000:8000 -n loadgen"
    Write-Host "  http://localhost:8000/metrics"
    Write-Host ""
    Write-Host "Grafana Dashboard:"
    Write-Host "  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    Write-Host "  http://localhost:3000"
    Write-Host "  Username: admin"
    Write-Host "  Password: admin"
    Write-Host ""
    Write-Host "View Load Generator Logs:"
    Write-Host "  kubectl logs -f deployment/loadgen -n loadgen"
    Write-Host ""
    Write-Host "View Grafana Logs:"
    Write-Host "  kubectl logs -f deployment/grafana -n monitoring"
    Write-Host ""
    Write-Host "Cluster Status:"
    Write-Host "  kubectl get pods -n loadgen"
    Write-Host "  kubectl get pods -n monitoring"
}

# Function to run load test
function Start-LoadTest {
    $RunTest = Read-Host "Would you like to run a load test now? (y/n)"
    if ($RunTest -match "^[Yy]$") {
        Write-Status "Running load test..."
        
        # Get current workload configuration
        $WorkloadType = kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.workload-type}'
        $Intensity = kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.load-intensity}'
        $Duration = kubectl get configmap loadgen-config -n loadgen -o jsonpath='{.data.duration}'
        
        Write-Status "Current configuration: Workload=$WorkloadType, Intensity=$Intensity, Duration=${Duration}s"
        
        # Restart deployment to trigger new load test
        kubectl rollout restart deployment/loadgen -n loadgen
        
        Write-Success "Load test started. Check Grafana dashboard for metrics."
    }
}

# Main execution
function Main {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    GKE Load Generator Deployment" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Test-Prerequisites
    $ClusterInfo = Get-ClusterInfo
    Set-KubectlConfig -ClusterInfo $ClusterInfo
    Test-GMPStatus -ClusterInfo $ClusterInfo
    Build-Image -ClusterInfo $ClusterInfo
    Deploy-Kubernetes -ClusterInfo $ClusterInfo
    Wait-Deployment
    Show-AccessInfo
    Start-LoadTest
    
    Write-Host ""
    Write-Success "Setup complete! Your load generator is now running on GKE."
}

# Run main function
Main
