# GKE Load Generator

A comprehensive load generation tool for Google Kubernetes Engine (GKE) workload simulation with integrated monitoring using Grafana and Google Managed Prometheus (GMP).

## Features

- **Multi-pattern load generation**: CPU, memory, network, and storage stress testing
- **Configurable workload profiles**: Burst, sustained, and variable load patterns
- **Real-time monitoring**: Grafana dashboards for K8s control plane and application metrics
- **GMP integration**: Native Google Cloud monitoring with Prometheus compatibility
- **Easy deployment**: One-command deployment to any GKE cluster
- **Customizable**: Configurable load parameters and test scenarios

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Load Gen      │    │   GKE Cluster    │    │   Grafana       │
│   Application   │───▶│   + GMP          │───▶│   Dashboards    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Prerequisites

- GKE cluster with GMP enabled
- kubectl configured for your cluster
- Google Cloud CLI (gcloud) installed
- Docker or container runtime

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/loadgen-gke.git
   cd loadgen-gke
   ```

2. **Deploy to your GKE cluster**
   ```bash
   ./deploy.sh
   ```

3. **Access Grafana dashboard**
   ```bash
   kubectl port-forward svc/grafana 3000:3000 -n monitoring
   ```
   Open http://localhost:3000 in your browser

## Configuration

The load generator can be configured through ConfigMaps and environment variables:

- `WORKLOAD_TYPE`: CPU, MEMORY, NETWORK, STORAGE, or MIXED
- `LOAD_INTENSITY`: Low, Medium, High, or Custom
- `DURATION`: Test duration in seconds
- `BURST_PATTERN`: Enable/disable burst load patterns

## Monitoring

### Grafana Dashboards

- **K8s Control Plane**: API server, scheduler, controller manager metrics
- **Node Metrics**: CPU, memory, network, and disk utilization
- **Application Metrics**: Load generator performance and resource usage
- **GMP Integration**: Native Google Cloud monitoring metrics

### Key Metrics

- Cluster resource utilization
- Load generator performance
- Control plane health
- Node stress levels
- Network throughput

## Customization

### Adding New Workload Patterns

1. Extend the `WorkloadGenerator` class in `src/loadgen.py`
2. Add configuration options in `k8s/configmap.yaml`
3. Update Grafana dashboards for new metrics

### Custom Dashboards

1. Modify `grafana/dashboards/` files
2. Add new data sources in `grafana/datasources/`
3. Update deployment scripts

## Troubleshooting

### Common Issues

- **GMP not enabled**: Ensure Google Managed Prometheus is enabled on your cluster
- **Permission errors**: Verify RBAC permissions for monitoring namespace
- **Dashboard not loading**: Check Grafana data source configuration

### Logs

```bash
# Load generator logs
kubectl logs -f deployment/loadgen -n loadgen

# Grafana logs
kubectl logs -f deployment/grafana -n monitoring
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- GitHub Issues: [Create an issue](https://github.com/yourusername/loadgen-gke/issues)
- Documentation: [Wiki](https://github.com/yourusername/loadgen-gke/wiki)
