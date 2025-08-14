# Quick Start Guide

Get your GKE Load Generator up and running in minutes!

## Prerequisites

- GKE cluster with GMP enabled (or willingness to enable it)
- `gcloud` CLI configured
- `kubectl` installed
- `docker` installed
- Access to Google Container Registry (GCR)

## Step 1: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/loadgen-gke.git
cd loadgen-gke

# Make scripts executable
chmod +x deploy.sh configure-workload.sh cleanup.sh
```

## Step 2: Deploy

```bash
# Run the deployment script
./deploy.sh
```

The script will:
- Detect your GKE cluster
- Check GMP status
- Build and push the Docker image
- Deploy all components
- Configure monitoring

## Step 3: Access Dashboards

```bash
# Access Grafana (default: admin/admin)
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Access load generator metrics
kubectl port-forward svc/loadgen-service 8000:8000 -n loadgen
```

## Step 4: Configure Workloads

```bash
# Interactive configuration
./configure-workload.sh

# Or apply predefined profiles
kubectl apply -f examples/workload-profiles.yaml
kubectl patch configmap loadgen-config -n loadgen --patch-file examples/workload-profiles.yaml
```

## Step 5: Run Load Tests

```bash
# Restart with new configuration
kubectl rollout restart deployment/loadgen -n loadgen

# Monitor progress
kubectl logs -f deployment/loadgen -n loadgen
```

## Quick Commands

```bash
# Check status
kubectl get pods -n loadgen
kubectl get pods -n monitoring

# View logs
kubectl logs deployment/loadgen -n loadgen
kubectl logs deployment/grafana -n monitoring

# Check metrics
curl http://localhost:8000/metrics

# Cleanup when done
./cleanup.sh
```

## Troubleshooting

### Common Issues

1. **Image pull errors**: Ensure you have access to GCR
2. **Permission denied**: Check RBAC and cluster permissions
3. **GMP not working**: Verify GMP is enabled on your cluster
4. **Dashboard not loading**: Check Grafana pod status and logs

### Getting Help

- Check pod logs: `kubectl logs -f deployment/loadgen -n loadgen`
- Verify services: `kubectl get svc -n loadgen`
- Check events: `kubectl get events -n loadgen --sort-by='.lastTimestamp'`

## Next Steps

- Customize workload profiles in `examples/workload-profiles.yaml`
- Add custom Grafana dashboards
- Integrate with your CI/CD pipeline
- Set up alerts and notifications

## Support

- GitHub Issues: [Create an issue](https://github.com/yourusername/loadgen-gke/issues)
- Documentation: [Full README](README.md)
- Examples: [Workload Profiles](examples/workload-profiles.yaml)
