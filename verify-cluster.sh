#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "ClickHouse Cluster Health Check"
echo "=========================================="
echo ""

# Load credentials
if [ -f .credentials ]; then
  ADMIN_PASS=$(grep "Password:" .credentials | head -1 | awk '{print $2}')
else
  echo -e "${YELLOW}Warning: .credentials file not found. Using password from environment.${NC}"
  read -sp "Enter admin password: " ADMIN_PASS
  echo
fi

# Check Docker containers
echo "1. Checking Docker containers..."
if docker-compose ps | grep -q "Up"; then
  echo -e "${GREEN}✓${NC} Docker containers running"
  docker-compose ps --format "table {{.Name}}\t{{.Status}}" | head -12
else
  echo -e "${RED}✗${NC} Some containers are not running"
  docker-compose ps
  exit 1
fi
echo ""

# Check ClickHouse connectivity
echo "2. Checking ClickHouse connectivity..."
for i in {01..04}; do
  port=$((10000 + $i * 10000 + 8123))
  if curl -s http://localhost:${port}/ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} clickhouse-$i responding on port $port"
  else
    echo -e "${RED}✗${NC} clickhouse-$i not responding on port $port"
  fi
done
echo ""

# Check load balancer
echo "3. Checking HAProxy load balancer..."
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} HAProxy load balancer responding on port 8123"
else
  echo -e "${RED}✗${NC} HAProxy load balancer not responding"
fi
echo ""

# Check cluster topology
echo "4. Checking cluster topology..."
CLUSTER_CHECK=$(docker exec clickhouse-01 clickhouse-client \
  --user admin \
  --password "$ADMIN_PASS" \
  --query "SELECT cluster, shard_num, replica_num, host_name FROM system.clusters WHERE cluster = 'my_cluster' FORMAT TabSeparated" 2>&1)

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} Cluster 'my_cluster' configured correctly"
  echo "$CLUSTER_CHECK" | column -t -s $'\t'
else
  echo -e "${RED}✗${NC} Failed to query cluster topology"
  echo "$CLUSTER_CHECK"
  exit 1
fi
echo ""

# Check Keeper status
echo "5. Checking ClickHouse Keeper status..."
for i in {01..03}; do
  status=$(echo "mntr" | docker exec -i clickhouse-keeper-$i nc 127.0.0.1 9181 2>/dev/null | grep zk_server_state | awk '{print $2}')
  if [ -n "$status" ]; then
    echo -e "${GREEN}✓${NC} clickhouse-keeper-$i: $status"
  else
    echo -e "${RED}✗${NC} clickhouse-keeper-$i: not responding"
  fi
done
echo ""

# Check replication status
echo "6. Checking replication status..."
REPLICATION_CHECK=$(docker exec clickhouse-01 clickhouse-client \
  --user admin \
  --password "$ADMIN_PASS" \
  --query "SELECT count() as replica_count FROM system.replicas" 2>&1)

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} Replication configured (tables with replication: $REPLICATION_CHECK)"
else
  echo "No replicated tables yet (this is normal for new clusters)"
fi
echo ""

# Check monitoring (if enabled)
echo "7. Checking monitoring services..."
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Prometheus running on port 9090"
else
  echo -e "${YELLOW}⚠${NC}  Prometheus not running (use --profile monitoring to enable)"
fi

if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Grafana running on port 3000"
else
  echo -e "${YELLOW}⚠${NC}  Grafana not running (use --profile monitoring to enable)"
fi
echo ""

echo "=========================================="
echo -e "${GREEN}Cluster Health Check Complete!${NC}"
echo "=========================================="
echo ""
echo "Access points:"
echo "  • ClickHouse (HTTP):  http://localhost:8123"
echo "  • HAProxy Stats:      http://localhost:8404"
echo "  • Prometheus:         http://localhost:9090"
echo "  • Grafana:            http://localhost:3000"
echo ""
echo "Quick test query:"
echo "  docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query 'SELECT version()'"
echo ""
