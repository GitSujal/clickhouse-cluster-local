#!/bin/bash
set -e

echo "=========================================="
echo "ClickHouse Cluster Setup Script"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load environment variables from .env file
if [ -f .env ]; then
  echo "Loading environment variables from .env..."
  export $(grep -v '^#' .env | xargs)
  echo -e "${GREEN}✓${NC} Environment variables loaded"
else
  echo -e "${RED}✗${NC} .env file not found!"
  echo "Please create a .env file based on .env.example"
  exit 1
fi

# Validate required environment variables
if [ -z "$CLICKHOUSE_ADMIN_PASSWORD_SHA256" ] || [ -z "$CLICKHOUSE_APP_USER_PASSWORD_SHA256" ]; then
  echo -e "${RED}✗${NC} Missing required ClickHouse password variables in .env"
  echo "Required: CLICKHOUSE_ADMIN_PASSWORD_SHA256, CLICKHOUSE_APP_USER_PASSWORD_SHA256"
  exit 1
fi

if [ -z "$HAPROXY_STATS_USER" ] || [ -z "$HAPROXY_STATS_PASSWORD" ]; then
  echo -e "${RED}✗${NC} Missing required HAProxy variables in .env"
  echo "Required: HAPROXY_STATS_USER, HAPROXY_STATS_PASSWORD"
  exit 1
fi

# Create directory structure
echo "Creating directory structure..."
for i in {01..03}; do
  mkdir -p fs/volumes/clickhouse-keeper-${i}/etc/clickhouse-keeper
done

for i in {01..04}; do
  mkdir -p fs/volumes/clickhouse-${i}/etc/clickhouse-server/config.d
  mkdir -p fs/volumes/clickhouse-${i}/etc/clickhouse-server/users.d
done

mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards

echo -e "${GREEN}✓${NC} Directories created"

# Generate ClickHouse Server configs
echo "Generating ClickHouse server configs..."
for i in {01..04}; do
  # Determine shard and replica
  if [ "$i" = "01" ] || [ "$i" = "03" ]; then
    shard="01"
  else
    shard="02"
  fi

  if [ "$i" = "01" ] || [ "$i" = "02" ]; then
    replica="01"
  else
    replica="02"
  fi

  node_num=${i#0}  # Remove leading zero for display name

  cat > fs/volumes/clickhouse-${i}/etc/clickhouse-server/config.d/config.xml << EOF
<clickhouse replace="true">
    <logger>
        <level>information</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>3</count>
    </logger>
    <display_name>my_cluster node ${node_num}</display_name>
    <listen_host>0.0.0.0</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <user_directories>
        <users_xml>
            <path>users.xml</path>
        </users_xml>
        <local_directory>
            <path>/var/lib/clickhouse/access/</path>
        </local_directory>
    </user_directories>
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
    <remote_servers>
        <my_cluster>
            <shard>
                <internal_replication>true</internal_replication>
                <replica>
                    <host>clickhouse-01</host>
                    <port>9000</port>
                    <user>admin</user>
                    <password>test_admin_password_12345</password>
                </replica>
                <replica>
                    <host>clickhouse-03</host>
                    <port>9000</port>
                    <user>admin</user>
                    <password>test_admin_password_12345</password>
                </replica>
            </shard>
            <shard>
                <internal_replication>true</internal_replication>
                <replica>
                    <host>clickhouse-02</host>
                    <port>9000</port>
                    <user>admin</user>
                    <password>test_admin_password_12345</password>
                </replica>
                <replica>
                    <host>clickhouse-04</host>
                    <port>9000</port>
                    <user>admin</user>
                    <password>test_admin_password_12345</password>
                </replica>
            </shard>
        </my_cluster>
    </remote_servers>
    <zookeeper>
        <node>
            <host>clickhouse-keeper-01</host>
            <port>9181</port>
        </node>
        <node>
            <host>clickhouse-keeper-02</host>
            <port>9181</port>
        </node>
        <node>
            <host>clickhouse-keeper-03</host>
            <port>9181</port>
        </node>
    </zookeeper>
    <macros>
        <shard>${shard}</shard>
        <replica>${replica}</replica>
    </macros>
    <prometheus>
        <endpoint>/metrics</endpoint>
        <port>9363</port>
        <metrics>true</metrics>
        <events>true</events>
        <asynchronous_metrics>true</asynchronous_metrics>
        <errors>true</errors>
    </prometheus>
</clickhouse>
EOF
done

echo -e "${GREEN}✓${NC} ClickHouse server configs generated (4 nodes)"

# Generate ClickHouse Users configs
echo "Generating ClickHouse user configs..."
for i in {01..04}; do
  cat > fs/volumes/clickhouse-${i}/etc/clickhouse-server/users.d/users.xml << EOF
<?xml version="1.0"?>
<clickhouse replace="true">
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <max_execution_time>300</max_execution_time>
            <max_rows_to_read>1000000000</max_rows_to_read>
            <max_bytes_to_read>100000000000</max_bytes_to_read>
            <timeout_overflow_mode>throw</timeout_overflow_mode>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>in_order</load_balancing>
            <log_queries>1</log_queries>
        </default>
        <readonly>
            <readonly>1</readonly>
            <max_execution_time>60</max_execution_time>
            <max_memory_usage>5000000000</max_memory_usage>
        </readonly>
    </profiles>
    <users>
        <!-- Admin user with full privileges -->
        <admin>
            <password_sha256_hex>${CLICKHOUSE_ADMIN_PASSWORD_SHA256}</password_sha256_hex>
            <access_management>1</access_management>
            <profile>default</profile>
            <networks>
                <ip>127.0.0.1</ip>
                <ip>::1</ip>
                <ip>172.16.0.0/12</ip>
            </networks>
            <quota>default</quota>
            <named_collection_control>1</named_collection_control>
            <show_named_collections>1</show_named_collections>
            <show_named_collections_secrets>0</show_named_collections_secrets>
        </admin>

        <!-- Application user with limited privileges -->
        <app_user>
            <password_sha256_hex>${CLICKHOUSE_APP_USER_PASSWORD_SHA256}</password_sha256_hex>
            <profile>default</profile>
            <networks>
                <ip>127.0.0.1</ip>
                <ip>::1</ip>
                <ip>172.16.0.0/12</ip>
            </networks>
            <quota>default</quota>
            <named_collection_control>0</named_collection_control>
            <show_named_collections>0</show_named_collections>
            <show_named_collections_secrets>0</show_named_collections_secrets>
        </app_user>

        <!-- Default user - disabled for security -->
        <default>
            <access_management>0</access_management>
            <profile>readonly</profile>
            <networks>
                <ip>127.0.0.1</ip>
            </networks>
            <quota>default</quota>
        </default>
    </users>
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF
done

echo -e "${GREEN}✓${NC} ClickHouse user configs generated (4 nodes)"

# Generate ClickHouse Keeper configs
echo "Generating ClickHouse Keeper configs..."
for i in 01 02 03; do
  server_id=${i#0}  # Remove leading zero

  cat > fs/volumes/clickhouse-keeper-${i}/etc/clickhouse-keeper/keeper_config.xml << EOF
<clickhouse replace="true">
    <logger>
        <level>information</level>
        <log>/var/log/clickhouse-keeper/clickhouse-keeper.log</log>
        <errorlog>/var/log/clickhouse-keeper/clickhouse-keeper.err.log</errorlog>
        <size>1000M</size>
        <count>3</count>
    </logger>
    <listen_host>0.0.0.0</listen_host>
    <keeper_server>
        <tcp_port>9181</tcp_port>
        <server_id>${server_id}</server_id>
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
        <coordination_settings>
            <operation_timeout_ms>10000</operation_timeout_ms>
            <session_timeout_ms>30000</session_timeout_ms>
            <raft_logs_level>information</raft_logs_level>
        </coordination_settings>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>clickhouse-keeper-01</hostname>
                <port>9234</port>
            </server>
            <server>
                <id>2</id>
                <hostname>clickhouse-keeper-02</hostname>
                <port>9234</port>
            </server>
            <server>
                <id>3</id>
                <hostname>clickhouse-keeper-03</hostname>
                <port>9234</port>
            </server>
        </raft_configuration>
    </keeper_server>
    <prometheus>
        <port>9182</port>
    </prometheus>
</clickhouse>
EOF
done

echo -e "${GREEN}✓${NC} ClickHouse Keeper configs generated (3 keepers)"

# Generate HAProxy configs
echo "Generating HAProxy configs..."

# HTTP-only config
cat > haproxy-http.cfg << EOF
global
    maxconn 4096
    log stdout format raw local0
    # TLS settings
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Stats page (HTTP) - secured with authentication
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats show-node
    stats auth ${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}

# ClickHouse HTTP interface (port 8123) - Non-TLS
frontend clickhouse_http
    bind *:8123
    mode http
    default_backend clickhouse_http_backend

backend clickhouse_http_backend
    mode http
    balance roundrobin
    option httpchk GET /ping
    http-check expect status 200
    server clickhouse-01 clickhouse-01:8123 check inter 5s fall 3 rise 2
    server clickhouse-02 clickhouse-02:8123 check inter 5s fall 3 rise 2
    server clickhouse-03 clickhouse-03:8123 check inter 5s fall 3 rise 2
    server clickhouse-04 clickhouse-04:8123 check inter 5s fall 3 rise 2

# ClickHouse Native TCP interface (port 9000) - Non-TLS
frontend clickhouse_tcp
    bind *:9000
    mode tcp
    default_backend clickhouse_tcp_backend

# Note: TLS for native TCP protocol requires ClickHouse server-side configuration
# This HAProxy config focuses on HTTP/HTTPS load balancing

backend clickhouse_tcp_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server clickhouse-01 clickhouse-01:9000 check inter 5s fall 3 rise 2
    server clickhouse-02 clickhouse-02:9000 check inter 5s fall 3 rise 2
    server clickhouse-03 clickhouse-03:9000 check inter 5s fall 3 rise 2
    server clickhouse-04 clickhouse-04:9000 check inter 5s fall 3 rise 2
EOF

# HTTPS config with TLS termination
cat > haproxy-https.cfg << EOF
global
    maxconn 4096
    log stdout format raw local0
    # TLS settings
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Stats page (HTTP) - for backward compatibility (secured with authentication)
listen stats_http
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats show-node
    stats auth ${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}

# Stats page (HTTPS) - secure stats
listen stats_https
    bind *:8405 ssl crt /usr/local/etc/haproxy/certs/server.pem
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats show-node
    stats auth ${HAPROXY_STATS_USER}:${HAPROXY_STATS_PASSWORD}

# ClickHouse HTTP interface (port 8123) - backward compatibility
frontend clickhouse_http
    bind *:8123
    mode http
    # Optional: Uncomment to redirect HTTP to HTTPS
    # redirect scheme https code 301 if !{ ssl_fc }
    default_backend clickhouse_http_backend

# ClickHouse HTTPS interface (port 8443) - TLS termination
frontend clickhouse_https
    bind *:8443 ssl crt /usr/local/etc/haproxy/certs/server.pem
    mode http
    # Security headers
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-Frame-Options DENY
    http-response set-header X-XSS-Protection "1; mode=block"
    default_backend clickhouse_http_backend

backend clickhouse_http_backend
    mode http
    balance roundrobin
    option httpchk GET /ping
    http-check expect status 200
    server clickhouse-01 clickhouse-01:8123 check inter 5s fall 3 rise 2
    server clickhouse-02 clickhouse-02:8123 check inter 5s fall 3 rise 2
    server clickhouse-03 clickhouse-03:8123 check inter 5s fall 3 rise 2
    server clickhouse-04 clickhouse-04:8123 check inter 5s fall 3 rise 2

# ClickHouse Native TCP interface (port 9000) - no TLS
# Note: TLS for native protocol requires ClickHouse server-side configuration
frontend clickhouse_tcp
    bind *:9000
    mode tcp
    default_backend clickhouse_tcp_backend

backend clickhouse_tcp_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server clickhouse-01 clickhouse-01:9000 check inter 5s fall 3 rise 2
    server clickhouse-02 clickhouse-02:9000 check inter 5s fall 3 rise 2
    server clickhouse-03 clickhouse-03:9000 check inter 5s fall 3 rise 2
    server clickhouse-04 clickhouse-04:9000 check inter 5s fall 3 rise 2
EOF

echo -e "${GREEN}✓${NC} HAProxy configs generated (HTTP and HTTPS versions)"
echo "  • haproxy-http.cfg  - HTTP only"
echo "  • haproxy-https.cfg - HTTPS with TLS"

# Generate Prometheus config
echo "Generating Prometheus config..."
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'clickhouse_my_cluster'

# Alertmanager configuration (optional)
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Load rules once and periodically evaluate them
rule_files:
  # - "alert_rules.yml"

# Scrape configurations
scrape_configs:
  # ClickHouse Server Nodes
  - job_name: 'clickhouse-servers'
    static_configs:
      - targets:
          - 'clickhouse-01:9363'
          - 'clickhouse-02:9363'
          - 'clickhouse-03:9363'
          - 'clickhouse-04:9363'
        labels:
          cluster: 'my_cluster'

  # ClickHouse Keeper Nodes
  - job_name: 'clickhouse-keepers'
    static_configs:
      - targets:
          - 'clickhouse-keeper-01:9182'
          - 'clickhouse-keeper-02:9182'
          - 'clickhouse-keeper-03:9182'
        labels:
          cluster: 'my_cluster'

  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets:
          - 'localhost:9090'
EOF

echo -e "${GREEN}✓${NC} Prometheus config generated"

# Generate Grafana provisioning files
echo "Generating Grafana provisioning configs..."
cat > grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s
      httpMethod: POST
EOF

cat > grafana/provisioning/dashboards/clickhouse.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'ClickHouse Dashboards'
    orgId: 1
    folder: 'ClickHouse'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

echo -e "${GREEN}✓${NC} Grafana provisioning configs generated"

# Check if Grafana dashboard exists
if [ ! -f "grafana/provisioning/dashboards/clickhouse-cluster-overview.json" ]; then
  echo -e "${YELLOW}⚠${NC}  Grafana dashboard JSON not generated (use existing or create custom)"
else
  echo -e "${GREEN}✓${NC} Grafana dashboard already exists"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "All configuration files have been generated:"
echo "  • 4 ClickHouse server configs"
echo "  • 3 ClickHouse Keeper configs"
echo "  • HAProxy load balancer config"
echo "  • Prometheus monitoring config"
echo "  • Grafana datasource & dashboard provisioning"
echo ""
echo "Next steps:"
echo "  1. Start cluster with desired profile:"
echo ""
echo "     Basic (ClickHouse only):"
echo "       docker-compose --profile basic --profile loadbalancer up -d"
echo ""
echo "     With monitoring:"
echo "       docker-compose --profile basic --profile loadbalancer --profile monitoring up -d"
echo ""
echo "     With HTTPS (requires certificates):"
echo "       ./generate-certs.sh"
echo "       docker-compose --profile basic --profile tls up -d"
echo ""
echo "  2. Wait ~30 seconds for cluster to initialize"
echo "  3. Verify: docker-compose ps"
echo ""
echo "Profiles available:"
echo "  • basic       - ClickHouse nodes + Keepers (required)"
echo "  • loadbalancer - HAProxy HTTP mode"
echo "  • tls         - HAProxy HTTPS mode (includes loadbalancer)"
echo "  • monitoring  - Prometheus + Grafana"
echo ""
echo "Access points:"
echo "  • ClickHouse (via HAProxy): http://localhost:8123"
echo "  • ClickHouse (HTTPS): https://localhost:8443 (with --profile tls)"
echo "  • HAProxy Stats: http://localhost:8404"
echo "  • Prometheus: http://localhost:9090 (with --profile monitoring)"
echo "  • Grafana: http://localhost:3000 (with --profile monitoring)"
echo ""
echo "Quick test:"
echo "  docker exec clickhouse-01 clickhouse-client --query 'SELECT version()'"
echo ""
