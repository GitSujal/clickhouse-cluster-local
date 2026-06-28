#!/bin/bash
set -e

echo "=========================================="
echo "ClickHouse Cluster - .env Generator"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to generate SHA256 hash
generate_sha256() {
  echo -n "$1" | sha256sum | awk '{print $1}'
}

# Function to generate random password
generate_random_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 32
}

# Check if .env already exists
if [ -f .env ]; then
  echo -e "${YELLOW}Warning: .env file already exists!${NC}"
  read -p "Do you want to overwrite it? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Generating .env file..."
echo ""

# Grafana admin password
echo -e "${GREEN}Grafana Configuration${NC}"
read -p "Enter Grafana admin username [admin]: " GF_USER
GF_USER=${GF_USER:-admin}

read -sp "Enter Grafana admin password (leave empty for random): " GF_PASS
echo
if [ -z "$GF_PASS" ]; then
  GF_PASS=$(generate_random_password)
  echo "Generated random password for Grafana admin"
fi

read -sp "Enter Grafana secret key (leave empty for random): " GF_SECRET
echo
if [ -z "$GF_SECRET" ]; then
  GF_SECRET=$(generate_random_password)
  echo "Generated random secret key for Grafana"
fi

# ClickHouse admin password
echo ""
echo -e "${GREEN}ClickHouse Admin User${NC}"
read -sp "Enter ClickHouse admin password (leave empty for random): " CH_ADMIN_PASS
echo
if [ -z "$CH_ADMIN_PASS" ]; then
  CH_ADMIN_PASS=$(generate_random_password)
  echo "Generated random password for ClickHouse admin"
fi
CH_ADMIN_HASH=$(generate_sha256 "$CH_ADMIN_PASS")

# ClickHouse app user password
echo ""
echo -e "${GREEN}ClickHouse Application User${NC}"
read -sp "Enter ClickHouse app_user password (leave empty for random): " CH_APP_PASS
echo
if [ -z "$CH_APP_PASS" ]; then
  CH_APP_PASS=$(generate_random_password)
  echo "Generated random password for ClickHouse app_user"
fi
CH_APP_HASH=$(generate_sha256 "$CH_APP_PASS")

# HAProxy stats password
echo ""
echo -e "${GREEN}HAProxy Stats Authentication${NC}"
read -p "Enter HAProxy stats username [admin]: " HAPROXY_USER
HAPROXY_USER=${HAPROXY_USER:-admin}

read -sp "Enter HAProxy stats password (leave empty for random): " HAPROXY_PASS
echo
if [ -z "$HAPROXY_PASS" ]; then
  HAPROXY_PASS=$(generate_random_password)
  echo "Generated random password for HAProxy stats"
fi

# Write .env file
cat > .env << EOF
# Grafana Configuration
GF_SECURITY_ADMIN_USER=$GF_USER
GF_SECURITY_ADMIN_PASSWORD=$GF_PASS
GF_SECURITY_SECRET_KEY=$GF_SECRET

# ClickHouse Passwords (SHA256 hashes)
CLICKHOUSE_ADMIN_PASSWORD_SHA256=$CH_ADMIN_HASH
CLICKHOUSE_APP_USER_PASSWORD_SHA256=$CH_APP_HASH

# HAProxy Stats Authentication
HAPROXY_STATS_USER=$HAPROXY_USER
HAPROXY_STATS_PASSWORD=$HAPROXY_PASS
EOF

# Create credentials file for reference (not loaded by docker-compose)
cat > .credentials << EOF
========================================
ClickHouse Cluster - Credentials
========================================
Generated: $(date)

GRAFANA
--------
Username: $GF_USER
Password: $GF_PASS
URL:      http://localhost:3000

CLICKHOUSE
----------
Admin User:
  Username: admin
  Password: $CH_ADMIN_PASS

Application User:
  Username: app_user
  Password: $CH_APP_PASS

HAPROXY STATS
-------------
Username: $HAPROXY_USER
Password: $HAPROXY_PASS
URL:      http://localhost:8404

========================================
IMPORTANT: Store these credentials safely!
This file (.credentials) is for your reference only.
It should be added to .gitignore.
========================================
EOF

chmod 600 .credentials

echo ""
echo -e "${GREEN}✓${NC} .env file created successfully!"
echo -e "${GREEN}✓${NC} Credentials saved to .credentials"
echo ""
echo "Summary:"
echo "  • Grafana admin: $GF_USER"
echo "  • ClickHouse admin password hash: $CH_ADMIN_HASH"
echo "  • ClickHouse app_user password hash: $CH_APP_HASH"
echo "  • HAProxy stats user: $HAPROXY_USER"
echo ""
echo "Plain-text passwords are stored in .credentials (for your reference)"
echo "Make sure to add .env and .credentials to .gitignore!"
echo ""
echo "Next step: Run ./setup.sh to generate configuration files"
