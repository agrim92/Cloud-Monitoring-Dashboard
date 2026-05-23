# Cloud Infrastructure Monitoring Dashboard

A production-grade observability stack built with **Prometheus**, **Grafana**, and **Node Exporter** — deployed on AWS EC2. Monitors CPU, memory, disk, and network metrics in real time with automated threshold-based alerting.

> Built as part of a hands-on SRE portfolio to demonstrate cloud monitoring and infrastructure observability skills.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS EC2 Instance                      │
│                                                              │
│   ┌─────────────────┐        ┌──────────────────────────┐   │
│   │  Node Exporter  │──────▶ │       Prometheus         │   │
│   │   (port 9100)   │ scrape │    (port 9090)           │   │
│   │                 │        │  - Stores time-series    │   │
│   │ Exposes system  │        │  - Evaluates alert rules │   │
│   │ metrics: CPU,   │        │  - PromQL query engine   │   │
│   │ memory, disk,   │        └────────────┬─────────────┘   │
│   │ network, etc.   │                     │                  │
│   └─────────────────┘              queries│                  │
│                                           ▼                  │
│                              ┌────────────────────────┐      │
│                              │        Grafana          │      │
│                              │     (port 3000)         │      │
│                              │  - Dashboards           │      │
│                              │  - Alert rules & UI     │      │
│                              │  - Provisioned auto     │      │
│                              └────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

**Data flow:** Node Exporter exposes raw metrics → Prometheus scrapes every 15s and stores them → Grafana queries Prometheus via PromQL and visualizes on dashboards → Alert rules fire when thresholds are breached.

---

## Features

- **Real-time metrics** — CPU, memory, disk, network I/O scraped every 15 seconds
- **5 alert rules** — Warning + critical thresholds for CPU, memory, disk, and instance availability
- **Auto-provisioned Grafana** — Dashboard and datasource load automatically on startup
- **Two deployment options** — Docker Compose (local/dev) or bare-metal script (EC2/production)
- **PromQL queries** — Multi-mode CPU breakdown (user/system/iowait), memory breakdown (used/cache/available)
- **Instance dropdown** — Filter dashboard by specific host using Grafana template variables

---

## Dashboard Preview

| Panel | Metric | Alert Threshold |
|-------|--------|-----------------|
| CPU Usage % | `100 - idle` | Warning >80%, Critical >95% |
| Memory Usage % | `1 - available/total` | Warning >85%, Critical >95% |
| Disk Usage % | `1 - avail/size` on `/` | Warning >75%, Critical >90% |
| Network Traffic | RX/TX bytes/sec | Warning >100 MB/s |
| Instance Status | `up` metric | Fires after 1 min down |
| Active Alerts | `ALERTS{alertstate="firing"}` | — |

---

## Quick Start — Docker Compose (Local)

Prerequisites: Docker + Docker Compose installed.

```bash
git clone https://github.com/YOUR_USERNAME/cloud-monitoring-dashboard.git
cd cloud-monitoring-dashboard
docker compose up -d
```

Then open:
- **Grafana**: http://localhost:3000 (login: `admin` / `admin`)
- **Prometheus**: http://localhost:9090
- **Node Exporter metrics**: http://localhost:9100/metrics

The dashboard loads automatically. No manual import needed.

---

## Deploy on AWS EC2

### 1. Launch an EC2 instance
- AMI: Ubuntu 22.04 LTS
- Instance type: `t2.micro` (free tier eligible)
- Security group: open inbound ports **9090**, **9100**, **3000** (TCP)

### 2. SSH and clone the repo

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
git clone https://github.com/YOUR_USERNAME/cloud-monitoring-dashboard.git
cd cloud-monitoring-dashboard
```

### 3. Run the setup script

```bash
sudo bash scripts/setup.sh
```

The script installs Prometheus, Node Exporter, and Grafana as systemd services.

### 4. Access the stack

```
Prometheus  →  http://<EC2_PUBLIC_IP>:9090
Grafana     →  http://<EC2_PUBLIC_IP>:3000  (admin / admin)
Node Exp.   →  http://<EC2_PUBLIC_IP>:9100/metrics
```

---

## Alert Rules

All rules defined in `prometheus/alert_rules.yml`:

```yaml
# Example — fires if CPU stays above 80% for 5 minutes
- alert: HighCPUUsage
  expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High CPU on {{ $labels.instance }}"
```

To extend alerting to Slack or email, configure Alertmanager and uncomment the `alerting:` block in `prometheus/prometheus.yml`.

---

## Project Structure

```
cloud-monitoring-dashboard/
├── prometheus/
│   ├── prometheus.yml       # Scrape configs + rule references
│   └── alert_rules.yml      # CPU, memory, disk, network, uptime alerts
├── grafana/
│   ├── dashboard.json       # Full dashboard (import or auto-provisioned)
│   └── provisioning/
│       ├── datasources/     # Auto-connects Prometheus as data source
│       └── dashboards/      # Auto-loads dashboard.json
├── scripts/
│   └── setup.sh             # Bare-metal install script for EC2
├── docker-compose.yml       # Full stack for local development
└── README.md
```

---

## Key PromQL Queries

```promql
# CPU usage %
100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage %
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage % on root partition
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Network receive rate (bytes/sec)
rate(node_network_receive_bytes_total{device!~"lo"}[5m])
```

---

## Tech Stack

| Tool | Version | Role |
|------|---------|------|
| Prometheus | 2.51.0 | Metrics collection & storage |
| Node Exporter | 1.7.0 | System metrics exporter |
| Grafana | 10.4.2 | Visualization & alerting UI |
| Docker Compose | 3.8 | Local orchestration |
| AWS EC2 | Ubuntu 22.04 | Cloud deployment target |

---

## Extending This Project

- **Add more hosts** — drop additional targets into `prometheus.yml` under `node_exporter` job
- **AWS EC2 auto-discovery** — use `ec2_sd_configs` to auto-detect instances by tag
- **Alertmanager** — route alerts to Slack, PagerDuty, or email
- **CloudWatch integration** — use `yet-another-cloudwatch-exporter` (YACE) to pull AWS service metrics into Prometheus

---

## License

MIT
