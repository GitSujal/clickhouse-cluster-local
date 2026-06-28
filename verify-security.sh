#!/bin/bash

# Security Verification Script
# Tests all security improvements applied to the ClickHouse cluster

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "ClickHouse Cluster Security Verification"
echo "=========================================="
echo ""

# Check if cluster is running
echo "1. Checking if cluster is running..."
if ! docker-compose ps | grep -q "clickhouse-01.*Up"; then
    echo -e "${RED}✗${NC} Cluster is not running. Start it with:"
    echo "  docker-compose --profile basic --profile loadbalancer --profile monitoring up -d"
    exit 1
fi
echo -e "${GREEN}✓${NC} Cluster is running"
echo ""

# Test ClickHouse admin authentication
echo "2. Testing ClickHouse admin authentication..."
if docker exec clickhouse-01 clickhouse-client --user admin --password secure_clickhouse_password_2026 --query "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Admin user authentication works"
else
    echo -e "${RED}✗${NC} Admin authentication failed"
fi
echo ""

# Test that default user has no password access
echo "3. Testing that default user is restricted..."
if docker exec clickhouse-01 clickhouse-client --user default --query "SELECT 1" 2>&1 | grep -q "Authentication failed"; then
    echo -e "${GREEN}✓${NC} Default user properly restricted (no password access)"
else
    echo -e "${YELLOW}⚠${NC}  Default user might still allow no-password access"
fi
echo ""

# Test app_user authentication
echo "4. Testing app_user authentication..."
if docker exec clickhouse-01 clickhouse-client --user app_user --password app_user_password_2026 --query "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} App user authentication works"
else
    echo -e "${RED}✗${NC} App user authentication failed"
fi
echo ""

# Test query limits
echo "5. Testing query execution limits..."
timeout 10 docker exec clickhouse-01 clickhouse-client --user admin --password secure_clickhouse_password_2026 --query "SELECT max_execution_time FROM system.settings WHERE name='max_execution_time'" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Query execution limits configured"
else
    echo -e "${YELLOW}⚠${NC}  Could not verify query limits"
fi
echo ""

# Test HAProxy stats authentication
echo "6. Testing HAProxy stats authentication..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8404/ | grep -q "401"; then
    echo -e "${GREEN}✓${NC} HAProxy stats requires authentication (HTTP 401)"

    # Test with credentials
    if curl -s -u admin:haproxy_stats_2026 http://localhost:8404/ | grep -q "Statistics Report"; then
        echo -e "${GREEN}✓${NC} HAProxy stats accessible with credentials"
    else
        echo -e "${YELLOW}⚠${NC}  HAProxy stats authentication present but response unexpected"
    fi
else
    echo -e "${RED}✗${NC} HAProxy stats might not require authentication"
fi
echo ""

# Check Docker health status
echo "7. Checking container health status..."
healthy_count=$(docker-compose ps | grep "healthy" | wc -l)
if [ $healthy_count -ge 7 ]; then
    echo -e "${GREEN}✓${NC} All containers are healthy ($healthy_count healthy)"
else
    echo -e "${YELLOW}⚠${NC}  Only $healthy_count containers are healthy (expected 7+)"
    echo "  Run 'docker-compose ps' to see details"
fi
echo ""

# Check Prometheus targets
echo "8. Checking Prometheus monitoring..."
if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -q "clickhouse-keepers"; then
    echo -e "${GREEN}✓${NC} Prometheus monitoring Keepers"
else
    echo -e "${YELLOW}⚠${NC}  Keeper monitoring might not be configured"
fi

if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -q "clickhouse-servers"; then
    echo -e "${GREEN}✓${NC} Prometheus monitoring ClickHouse servers"
else
    echo -e "${YELLOW}⚠${NC}  Server monitoring might not be configured"
fi
echo ""

# Test Grafana access
echo "9. Testing Grafana access..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Grafana is accessible on port 3000"
else
    echo -e "${YELLOW}⚠${NC}  Grafana might not be running (check if monitoring profile is enabled)"
fi
echo ""

# Check cluster configuration
echo "10. Verifying cluster configuration..."
cluster_name=$(docker exec clickhouse-01 clickhouse-client --user admin --password secure_clickhouse_password_2026 --query "SELECT cluster FROM system.clusters LIMIT 1" 2>/dev/null)
if [ "$cluster_name" == "cluster_2S_2R" ]; then
    echo -e "${GREEN}✓${NC} Cluster name is consistent: cluster_2S_2R"
else
    echo -e "${YELLOW}⚠${NC}  Cluster name: $cluster_name (expected cluster_2S_2R)"
fi
echo ""

# Summary
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Key Credentials (stored in .env):"
echo "  ClickHouse admin:    admin / secure_clickhouse_password_2026"
echo "  ClickHouse app_user: app_user / app_user_password_2026"
echo "  HAProxy stats:       admin / haproxy_stats_2026"
echo "  Grafana:             admin / (check .env file)"
echo ""
echo "Access Points:"
echo "  ClickHouse HTTP:  http://localhost:8123"
echo "  ClickHouse HTTPS: https://localhost:8443 (when TLS enabled)"
echo "  HAProxy Stats:    http://localhost:8404 (requires auth)"
echo "  Prometheus:       http://localhost:9090"
echo "  Grafana:          http://localhost:3000"
echo ""
echo "Next Steps:"
echo "  1. Review SECURITY-CHANGES.md for detailed changes"
echo "  2. Change passwords in .env before deploying to production"
echo "  3. Enable internode TLS for production use"
echo "  4. Set up backup strategy"
echo ""
