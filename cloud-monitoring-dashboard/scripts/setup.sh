#!/bin/bash
# ============================================================
#  Cloud Monitoring Dashboard - Setup Script
#  Installs Prometheus + Node Exporter on Ubuntu/Debian
#  Run as root or with sudo: sudo bash setup.sh
# ============================================================

set -e

PROM_VERSION="2.51.0"
NODE_EXPORTER_VERSION="1.7.0"
GRAFANA_VERSION="10.4.2"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ── Prerequisites ──────────────────────────────────────────
log "Checking prerequisites..."
[[ "$EUID" -ne 0 ]] && fail "Please run as root: sudo bash setup.sh"
command -v wget >/dev/null 2>&1 || apt-get install -y wget
command -v curl >/dev/null 2>&1 || apt-get install -y curl
apt-get install -y adduser libfontconfig1 musl 2>/dev/null

# ── Prometheus ─────────────────────────────────────────────
log "Installing Prometheus v${PROM_VERSION}..."

# Create prometheus user (no login shell)
id -u prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus

# Download & extract
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
cd "prometheus-${PROM_VERSION}.linux-amd64"

# Install binaries
cp prometheus promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Create directories and copy config
mkdir -p /etc/prometheus /var/lib/prometheus
cp -r consoles/ console_libraries/ /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Copy our config files
cp /root/cloud-monitoring-dashboard/prometheus/prometheus.yml /etc/prometheus/prometheus.yml 2>/dev/null || \
  cp "$(dirname "$0")/../prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
cp /root/cloud-monitoring-dashboard/prometheus/alert_rules.yml /etc/prometheus/alert_rules.yml 2>/dev/null || \
  cp "$(dirname "$0")/../prometheus/alert_rules.yml" /etc/prometheus/alert_rules.yml
chown prometheus:prometheus /etc/prometheus/prometheus.yml /etc/prometheus/alert_rules.yml

# Systemd service
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --storage.tsdb.retention.time=15d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
log "Prometheus running on :9090"

# ── Node Exporter ──────────────────────────────────────────
log "Installing Node Exporter v${NODE_EXPORTER_VERSION}..."

id -u node_exporter &>/dev/null || useradd --no-create-home --shell /bin/false node_exporter

cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter - System Metrics
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
log "Node Exporter running on :9100"

# ── Grafana ────────────────────────────────────────────────
log "Installing Grafana v${GRAFANA_VERSION}..."

cd /tmp
wget -q "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb"
dpkg -i "grafana_${GRAFANA_VERSION}_amd64.deb"

# Auto-provision Prometheus datasource
mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
EOF

# Auto-provision our dashboard
mkdir -p /etc/grafana/provisioning/dashboards
cat > /etc/grafana/provisioning/dashboards/default.yml << 'EOF'
apiVersion: 1
providers:
  - name: Default
    folder: Cloud Monitoring
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

mkdir -p /var/lib/grafana/dashboards
SCRIPT_DIR="$(dirname "$0")"
cp "${SCRIPT_DIR}/../grafana/dashboard.json" /var/lib/grafana/dashboards/cloud_monitoring.json 2>/dev/null || \
  warn "Dashboard JSON not found — import manually from grafana/ folder"
chown -R grafana:grafana /var/lib/grafana/dashboards 2>/dev/null || true

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server
log "Grafana running on :3000 (admin / admin)"

# ── Summary ────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo "  Prometheus  →  http://$(hostname -I | awk '{print $1}'):9090"
echo "  Grafana     →  http://$(hostname -I | awk '{print $1}'):3000"
echo "  Node Exp.   →  http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo ""
echo "  Grafana login: admin / admin"
echo "  (You'll be asked to change password on first login)"
echo "============================================"
echo ""
warn "Make sure ports 9090, 9100, 3000 are open in your cloud security group / firewall"
