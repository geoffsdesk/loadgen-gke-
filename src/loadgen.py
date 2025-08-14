#!/usr/bin/env python3
"""
GKE Load Generator - Multi-pattern workload simulation tool
"""

import os
import time
import threading
import random
import signal
import sys
from typing import Dict, List, Optional
import psutil
import requests
from prometheus_client import start_http_server, Counter, Gauge, Histogram, Summary
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
LOAD_REQUESTS_TOTAL = Counter('loadgen_requests_total', 'Total load generation requests', ['workload_type'])
LOAD_DURATION = Histogram('loadgen_duration_seconds', 'Load generation duration', ['workload_type'])
RESOURCE_USAGE = Gauge('loadgen_resource_usage', 'Resource usage during load generation', ['resource_type', 'workload_type'])
ERROR_COUNT = Counter('loadgen_errors_total', 'Total errors during load generation', ['workload_type'])

class WorkloadGenerator:
    """Base class for different workload types"""
    
    def __init__(self, name: str, intensity: str = "medium"):
        self.name = name
        self.intensity = intensity
        self.running = False
        self.threads = []
        
        # Intensity mappings
        self.intensity_levels = {
            "low": {"cpu_percent": 20, "memory_mb": 100, "duration": 30},
            "medium": {"cpu_percent": 50, "memory_mb": 250, "duration": 60},
            "high": {"cpu_percent": 80, "memory_mb": 500, "duration": 120},
            "custom": {"cpu_percent": 70, "memory_mb": 300, "duration": 90}
        }
        
        self.config = self.intensity_levels.get(intensity, self.intensity_levels["medium"])
    
    def start(self):
        """Start the workload generation"""
        self.running = True
        logger.info(f"Starting {self.name} workload with {self.intensity} intensity")
        
    def stop(self):
        """Stop the workload generation"""
        self.running = False
        for thread in self.threads:
            if thread.is_alive():
                thread.join(timeout=5)
        logger.info(f"Stopped {self.name} workload")
    
    def cleanup(self):
        """Cleanup resources"""
        pass

class CPUWorkload(WorkloadGenerator):
    """CPU-intensive workload generator"""
    
    def __init__(self, intensity: str = "medium"):
        super().__init__("CPU", intensity)
    
    def start(self):
        super().start()
        # Start CPU stress threads
        for i in range(psutil.cpu_count()):
            thread = threading.Thread(target=self._cpu_stress, args=(i,))
            thread.daemon = True
            thread.start()
            self.threads.append(thread)
    
    def _cpu_stress(self, thread_id: int):
        """Generate CPU load"""
        while self.running:
            try:
                start_time = time.time()
                
                # CPU-intensive calculation
                result = 0
                for i in range(1000000):
                    result += i * i
                
                duration = time.time() - start_time
                LOAD_DURATION.labels(workload_type="cpu").observe(duration)
                LOAD_REQUESTS_TOTAL.labels(workload_type="cpu").inc()
                
                # Update resource metrics
                cpu_percent = psutil.cpu_percent(interval=1)
                RESOURCE_USAGE.labels(resource_type="cpu_percent", workload_type="cpu").set(cpu_percent)
                
                time.sleep(0.1)  # Small delay to prevent 100% CPU
                
            except Exception as e:
                logger.error(f"CPU workload error in thread {thread_id}: {e}")
                ERROR_COUNT.labels(workload_type="cpu").inc()

class MemoryWorkload(WorkloadGenerator):
    """Memory-intensive workload generator"""
    
    def __init__(self, intensity: str = "medium"):
        super().__init__("Memory", intensity)
        self.memory_chunks = []
    
    def start(self):
        super().start()
        thread = threading.Thread(target=self._memory_stress)
        thread.daemon = True
        thread.start()
        self.threads.append(thread)
    
    def _memory_stress(self):
        """Generate memory load"""
        chunk_size = self.config["memory_mb"] * 1024 * 1024  # Convert MB to bytes
        
        while self.running:
            try:
                start_time = time.time()
                
                # Allocate memory
                chunk = bytearray(chunk_size)
                self.memory_chunks.append(chunk)
                
                # Simulate memory operations
                for i in range(0, len(chunk), 1024):
                    chunk[i] = random.randint(0, 255)
                
                duration = time.time() - start_time
                LOAD_DURATION.labels(workload_type="memory").observe(duration)
                LOAD_REQUESTS_TOTAL.labels(workload_type="memory").inc()
                
                # Update resource metrics
                memory = psutil.virtual_memory()
                RESOURCE_USAGE.labels(resource_type="memory_percent", workload_type="memory").set(memory.percent)
                RESOURCE_USAGE.labels(resource_type="memory_used_mb", workload_type="memory").set(memory.used / 1024 / 1024)
                
                time.sleep(1)
                
            except Exception as e:
                logger.error(f"Memory workload error: {e}")
                ERROR_COUNT.labels(workload_type="memory").inc()
    
    def cleanup(self):
        """Free allocated memory"""
        self.memory_chunks.clear()
        super().cleanup()

class NetworkWorkload(WorkloadGenerator):
    """Network-intensive workload generator"""
    
    def __init__(self, intensity: str = "medium"):
        super().__init__("Network", intensity)
        self.endpoints = [
            "https://httpbin.org/get",
            "https://httpbin.org/post",
            "https://httpbin.org/status/200",
            "https://httpbin.org/delay/1"
        ]
    
    def start(self):
        super().start()
        # Start network stress threads
        for i in range(3):  # Multiple threads for concurrent requests
            thread = threading.Thread(target=self._network_stress, args=(i,))
            thread.daemon = True
            thread.start()
            self.threads.append(thread)
    
    def _network_stress(self, thread_id: int):
        """Generate network load"""
        while self.running:
            try:
                start_time = time.time()
                
                # Make HTTP requests
                for endpoint in self.endpoints:
                    if not self.running:
                        break
                    
                    response = requests.get(endpoint, timeout=10)
                    if response.status_code == 200:
                        LOAD_REQUESTS_TOTAL.labels(workload_type="network").inc()
                
                duration = time.time() - start_time
                LOAD_DURATION.labels(workload_type="network").observe(duration)
                
                # Update network metrics
                net_io = psutil.net_io_counters()
                RESOURCE_USAGE.labels(resource_type="network_bytes_sent", workload_type="network").set(net_io.bytes_sent)
                RESOURCE_USAGE.labels(resource_type="network_bytes_recv", workload_type="network").set(net_io.bytes_recv)
                
                time.sleep(2)
                
            except Exception as e:
                logger.error(f"Network workload error in thread {thread_id}: {e}")
                ERROR_COUNT.labels(workload_type="network").inc()

class StorageWorkload(WorkloadGenerator):
    """Storage-intensive workload generator"""
    
    def __init__(self, intensity: str = "medium"):
        super().__init__("Storage", intensity)
        self.temp_files = []
    
    def start(self):
        super().start()
        thread = threading.Thread(target=self._storage_stress)
        thread.daemon = True
        thread.start()
        self.threads.append(thread)
    
    def _storage_stress(self):
        """Generate storage load"""
        while self.running:
            try:
                start_time = time.time()
                
                # Create temporary files
                filename = f"/tmp/loadgen_storage_{int(time.time())}.dat"
                with open(filename, 'wb') as f:
                    # Write random data
                    data = bytearray(random.getrandbits(8) for _ in range(1024 * 1024))  # 1MB
                    f.write(data)
                
                self.temp_files.append(filename)
                
                # Read and process files
                for temp_file in self.temp_files[-5:]:  # Process last 5 files
                    if os.path.exists(temp_file):
                        with open(temp_file, 'rb') as f:
                            content = f.read()
                            # Simulate processing
                            checksum = sum(content)
                
                duration = time.time() - start_time
                LOAD_DURATION.labels(workload_type="storage").observe(duration)
                LOAD_REQUESTS_TOTAL.labels(workload_type="storage").inc()
                
                # Update storage metrics
                disk = psutil.disk_usage('/')
                RESOURCE_USAGE.labels(resource_type="disk_percent", workload_type="storage").set(disk.percent)
                RESOURCE_USAGE.labels(resource_type="disk_free_gb", workload_type="storage").set(disk.free / 1024 / 1024 / 1024)
                
                time.sleep(5)
                
            except Exception as e:
                logger.error(f"Storage workload error: {e}")
                ERROR_COUNT.labels(workload_type="storage").inc()
    
    def cleanup(self):
        """Clean up temporary files"""
        for temp_file in self.temp_files:
            try:
                if os.path.exists(temp_file):
                    os.remove(temp_file)
            except Exception as e:
                logger.warning(f"Could not remove temp file {temp_file}: {e}")
        self.temp_files.clear()
        super().cleanup()

class MixedWorkload(WorkloadGenerator):
    """Combined workload generator"""
    
    def __init__(self, intensity: str = "medium"):
        super().__init__("Mixed", intensity)
        self.workloads = [
            CPUWorkload(intensity),
            MemoryWorkload(intensity),
            NetworkWorkload(intensity),
            StorageWorkload(intensity)
        ]
    
    def start(self):
        super().start()
        for workload in self.workloads:
            workload.start()
    
    def stop(self):
        super().stop()
        for workload in self.workloads:
            workload.stop()
    
    def cleanup(self):
        for workload in self.workloads:
            workload.cleanup()
        super().cleanup()

class LoadGeneratorManager:
    """Manages multiple workload generators"""
    
    def __init__(self):
        self.workloads: Dict[str, WorkloadGenerator] = {}
        self.running = False
        self.signal_received = False
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.signal_received = True
        self.stop_all()
        sys.exit(0)
    
    def add_workload(self, workload_type: str, intensity: str = "medium"):
        """Add a workload generator"""
        workload_map = {
            "cpu": CPUWorkload,
            "memory": MemoryWorkload,
            "network": NetworkWorkload,
            "storage": StorageWorkload,
            "mixed": MixedWorkload
        }
        
        if workload_type not in workload_map:
            raise ValueError(f"Unknown workload type: {workload_type}")
        
        workload_class = workload_map[workload_type]
        self.workloads[workload_type] = workload_class(intensity)
        logger.info(f"Added {workload_type} workload with {intensity} intensity")
    
    def start_all(self):
        """Start all workload generators"""
        if not self.workloads:
            logger.warning("No workloads configured")
            return
        
        self.running = True
        for workload in self.workloads.values():
            workload.start()
        logger.info("All workloads started")
    
    def stop_all(self):
        """Stop all workload generators"""
        self.running = False
        for workload in self.workloads.values():
            workload.stop()
        logger.info("All workloads stopped")
    
    def cleanup_all(self):
        """Cleanup all workloads"""
        for workload in self.workloads.values():
            workload.cleanup()
        logger.info("All workloads cleaned up")

def main():
    """Main entry point"""
    # Get configuration from environment variables
    workload_type = os.getenv("WORKLOAD_TYPE", "mixed").lower()
    load_intensity = os.getenv("LOAD_INTENSITY", "medium").lower()
    duration = int(os.getenv("DURATION", "300"))  # 5 minutes default
    metrics_port = int(os.getenv("METRICS_PORT", "8000"))
    
    logger.info(f"Starting GKE Load Generator")
    logger.info(f"Workload: {workload_type}, Intensity: {load_intensity}, Duration: {duration}s")
    
    # Start Prometheus metrics server
    start_http_server(metrics_port)
    logger.info(f"Metrics server started on port {metrics_port}")
    
    # Create and configure workload manager
    manager = LoadGeneratorManager()
    manager.add_workload(workload_type, load_intensity)
    
    try:
        # Start workloads
        manager.start_all()
        
        # Run for specified duration
        start_time = time.time()
        while time.time() - start_time < duration and not manager.signal_received:
            time.sleep(1)
            
            # Log progress every 30 seconds
            elapsed = int(time.time() - start_time)
            if elapsed % 30 == 0:
                logger.info(f"Load generation running for {elapsed}s")
        
        logger.info("Load generation completed")
        
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        ERROR_COUNT.labels(workload_type=workload_type).inc()
    finally:
        # Cleanup
        manager.stop_all()
        manager.cleanup_all()
        logger.info("Load generator shutdown complete")

if __name__ == "__main__":
    main()
