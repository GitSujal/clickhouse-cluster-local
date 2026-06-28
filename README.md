# ClickHouse Cluster (2 Shards × 2 Replicas)

Production-ready ClickHouse cluster with load balancing, replication, and monitoring.

**Architecture:** 4 ClickHouse nodes, 3 ClickHouse Keeper nodes, HAProxy load balancer, Prometheus + Grafana monitoring.

## Quick Start

```bash
# 1. Generate secure credentials
./generate-env.sh

# 2. Generate cluster configuration files
./setup.sh

# 3. Start the cluster (choose one):
# Basic: ClickHouse + HTTP load balancer
docker-compose --profile basic --profile loadbalancer up -d

# With monitoring: Add Prometheus + Grafana
docker-compose --profile basic --profile loadbalancer --profile monitoring up -d

# With HTTPS: Requires certificates (see TLS section)
./generate-certs.sh
docker-compose --profile basic --profile tls --profile monitoring up -d

# 4. Verify (wait ~30 seconds for initialization)
./verify-cluster.sh
```

**Find your passwords in `.credentials` file after running `./generate-env.sh`**

---

## Table of Contents

1. [Architecture](#architecture)
2. [Setup](#setup)
3. [Working with the Cluster](#working-with-the-cluster)
4. [TLS/HTTPS Configuration](#tlshttps-configuration)
5. [Monitoring](#monitoring)
6. [Security](#security)
7. [Troubleshooting](#troubleshooting)
8. [Operations](#operations)

---

## Architecture

### Cluster Topology

```
Shard 1: clickhouse-01 (replica 1) + clickhouse-03 (replica 2)
Shard 2: clickhouse-02 (replica 1) + clickhouse-04 (replica 2)

Coordination: 3 ClickHouse Keeper nodes (quorum-based)
Load Balancer: HAProxy (round-robin across all 4 nodes)
Monitoring: Prometheus (metrics) + Grafana (dashboards)
```

### Port Mapping

| Service | Purpose | Port(s) |
|---------|---------|---------|
| **HAProxy** | Load-balanced HTTP | 8123 |
| | Load-balanced HTTPS | 8443 |
| | Load-balanced TCP | 9000 |
| | Stats page | 8404 (HTTP), 8405 (HTTPS) |
| **ClickHouse-01** | Direct HTTP | 18123 |
| | Direct TCP | 19000 |
| | Metrics | 19363 |
| **ClickHouse-02** | Direct HTTP | 28123 |
| | Direct TCP | 29000 |
| | Metrics | 29363 |
| **ClickHouse-03** | Direct HTTP | 38123 |
| | Direct TCP | 39000 |
| | Metrics | 39363 |
| **ClickHouse-04** | Direct HTTP | 48123 |
| | Direct TCP | 49000 |
| | Metrics | 49363 |
| **Keeper-01/02/03** | Client ports | 9181/9182/9183 |
| **Prometheus** | Metrics UI | 9090 |
| **Grafana** | Dashboards | 3000 |

All services bind to `127.0.0.1` for security.

### Docker Compose Profiles

| Profile | Services | Use Case |
|---------|----------|----------|
| `basic` | ClickHouse + Keepers | Required base |
| `loadbalancer` | HAProxy (HTTP) | HTTP load balancing |
| `tls` | HAProxy (HTTPS) | TLS termination |
| `monitoring` | Prometheus + Grafana | Metrics and visualization |

**Profile combinations:**
```bash
# Minimal
docker-compose --profile basic up -d

# Standard
docker-compose --profile basic --profile loadbalancer up -d

# Full stack with HTTPS
docker-compose --profile basic --profile tls --profile monitoring up -d
```

---

## Setup

### Prerequisites

- Docker & Docker Compose
- Bash (for setup scripts)
- 4GB+ RAM available

### Step 1: Generate Credentials

```bash
./generate-env.sh
```

This creates:
- `.env` - Environment variables with password hashes (used by Docker Compose)
- `.credentials` - Plain-text passwords for your reference

**Users created:**
- `admin` - Full cluster access
- `app_user` - Limited privileges for applications
- `default` - Read-only, localhost-only

**Important:** Never commit `.env` or `.credentials` to git!

### Step 2: Generate Configuration Files

```bash
./setup.sh
```

This generates:
- `fs/volumes/clickhouse-*/` - ClickHouse server configs (4 nodes)
- `fs/volumes/clickhouse-keeper-*/` - Keeper configs (3 nodes)
- `haproxy-http.cfg` - HTTP load balancer config
- `haproxy-https.cfg` - HTTPS load balancer config
- `prometheus.yml` - Metrics scraping config
- `grafana/provisioning/` - Grafana datasource config

**These files are git-ignored** (regenerate them with `./setup.sh` after credential changes).

### Step 3: Start the Cluster

```bash
# HTTP load balancer (development)
docker-compose --profile basic --profile loadbalancer up -d

# HTTPS load balancer (production) - requires certs
./generate-certs.sh  # Self-signed for development
docker-compose --profile basic --profile tls up -d

# With monitoring
docker-compose --profile basic --profile loadbalancer --profile monitoring up -d
```

Wait ~30 seconds for initialization.

### Step 4: Verify

```bash
# Run automated health check
./verify-cluster.sh
```

This script checks:
- ✅ Docker containers status
- ✅ ClickHouse node connectivity
- ✅ HAProxy load balancer
- ✅ Cluster topology
- ✅ Keeper quorum status
- ✅ Replication status
- ✅ Monitoring services (if enabled)

**Manual verification (if needed):**
```bash
# Test connection (replace YOUR_PASSWORD with value from .credentials)
docker exec clickhouse-01 clickhouse-client \
  --user admin \
  --password YOUR_PASSWORD \
  --query "SELECT version()"

# View cluster topology
docker exec clickhouse-01 clickhouse-client \
  --user admin \
  --password YOUR_PASSWORD \
  --query "SELECT cluster, shard_num, replica_num, host_name FROM system.clusters WHERE cluster = 'my_cluster'"
```

---

## Working with the Cluster

### Connect to ClickHouse

```bash
# Via clickhouse-client (inside container)
docker exec -it clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD

# Via HTTP (through load balancer)
curl "http://localhost:8123/?user=admin&password=YOUR_PASSWORD&query=SELECT+1"

# Via HTTPS (when TLS enabled)
curl "https://localhost:8443/?user=admin&password=YOUR_PASSWORD&query=SELECT+1"
```

### Create Replicated Database

```sql
CREATE DATABASE my_db ON CLUSTER my_cluster;
```

**Important:** Always use `ON CLUSTER my_cluster` to ensure consistency across all nodes.

### Create Replicated Table

```sql
-- Local table (automatically replicated within each shard)
CREATE TABLE my_db.events ON CLUSTER my_cluster
(
    event_time DateTime,
    user_id UInt64,
    event_type String,
    metadata String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/{table}/{shard}', '{replica}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time);

-- Distributed table (query interface across all shards)
CREATE TABLE my_db.events_distributed ON CLUSTER my_cluster
AS my_db.events
ENGINE = Distributed('my_cluster', 'my_db', 'events', rand());
```

**Key patterns:**
- **`{database}`**, **`{table}`**, **`{shard}`**, **`{replica}`** - Macros automatically substituted per node
- **`/clickhouse/tables/.../{shard}`** - Each shard has independent ZooKeeper path
- **`internal_replication=true`** - Insert to one replica, automatic replication to second

### Insert Data

```sql
-- Insert via distributed table (automatic sharding)
INSERT INTO my_db.events_distributed VALUES
    (now(), 1001, 'login', '{}'),
    (now(), 1002, 'click', '{"button":"submit"}'),
    (now(), 1003, 'logout', '{}');
```

### Query Data

```sql
-- Query from distributed table (aggregates all shards)
SELECT event_type, count() 
FROM my_db.events_distributed 
GROUP BY event_type;

-- Query local table (single node's data only)
SELECT count() FROM my_db.events;
```

### Manage Users

```sql
-- Create user on entire cluster
CREATE USER analyst ON CLUSTER my_cluster 
IDENTIFIED BY 'secure_password' 
HOST ANY;

-- Grant privileges
GRANT SELECT ON my_db.* TO analyst ON CLUSTER my_cluster;

-- Create admin user
CREATE USER new_admin ON CLUSTER my_cluster
IDENTIFIED BY 'admin_password'
HOST ANY;

GRANT ALL ON *.* TO new_admin WITH GRANT OPTION ON CLUSTER my_cluster;
```

**Always use `ON CLUSTER`** - Without it, users are only created on the node you're connected to.

---

## TLS/HTTPS Configuration

TLS termination happens at HAProxy (not ClickHouse nodes).

### Development (Self-Signed Certificate)

```bash
# 1. Generate certificate
./generate-certs.sh

# 2. Start with HTTPS
docker-compose --profile basic --profile tls up -d

# 3. Test (skip verification for self-signed)
curl -k https://localhost:8443/ping
```

### Production (Let's Encrypt)

```bash
# 1. Install certbot
sudo apt-get install certbot

# 2. Obtain certificate (requires public domain)
sudo certbot certonly --standalone -d yourdomain.com

# 3. Copy to certs/ directory
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem certs/server.crt
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem certs/server.key
cat certs/server.crt certs/server.key > certs/server.pem

# 4. Set permissions
chmod 600 certs/server.key certs/server.pem
chmod 644 certs/server.crt

# 5. Start with HTTPS
docker-compose --profile basic --profile tls up -d
```

### Certificate Renewal

```bash
# Renew (run monthly via cron)
sudo certbot renew

# Update certs
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem certs/server.crt
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem certs/server.key
cat certs/server.crt certs/server.key > certs/server.pem

# Restart HAProxy
docker-compose restart haproxy
```

### Switch Between HTTP and HTTPS

```bash
# Stop current services
docker-compose down

# Start with HTTP
docker-compose --profile basic --profile loadbalancer up -d

# OR start with HTTPS
docker-compose --profile basic --profile tls up -d
```

---

## Monitoring

### Prometheus

**URL:** http://localhost:9090

**Useful queries:**
```promql
# Query rate per node
rate(ClickHouseProfileEvents_Query[5m])

# Memory usage
ClickHouseMetrics_MemoryTracking

# Inserted rows per second
rate(ClickHouseProfileEvents_InsertedRows[5m])

# Failed queries
rate(ClickHouseProfileEvents_FailedQuery[5m])

# Keeper follower count
ClickHouseMetrics_KeeperAliveConnections
```

### Grafana

**URL:** http://localhost:3000  
**Credentials:** From `.credentials` file

**Pre-configured:**
- Prometheus datasource
- Auto-refresh dashboards
- ClickHouse cluster metrics

**Import additional dashboards:** Search grafana.com for "ClickHouse" dashboard IDs.

### HAProxy Stats

**URL:** http://localhost:8404 (HTTP) or https://localhost:8405 (HTTPS)  
**Credentials:** From `.credentials` file

**Shows:**
- Backend server health (green/red)
- Request distribution
- Connection statistics
- Failed health checks

---

## Security

### Credentials

All credentials are environment-based:

| Component | User | Password Location |
|-----------|------|-------------------|
| ClickHouse | `admin` | `.credentials` (plain-text) / `.env` (SHA256) |
| ClickHouse | `app_user` | `.credentials` (plain-text) / `.env` (SHA256) |
| Grafana | `admin` | `.credentials` |
| HAProxy Stats | `admin` | `.credentials` |

**NEVER commit** `.env`, `.credentials`, or `certs/` to git.

### Network Access

- **All services:** Bound to `127.0.0.1` (localhost only)
- **ClickHouse users:** Restricted to `127.0.0.1`, `::1`, and Docker network (`172.16.0.0/12`)
- **Default user:** Disabled (read-only, localhost-only)

### Production Hardening Checklist

- [ ] Generate unique passwords via `./generate-env.sh` (never use defaults)
- [ ] Store `.env` and `.credentials` in secure vault (HashiCorp Vault, AWS Secrets Manager)
- [ ] Enable TLS with trusted CA certificates (not self-signed)
- [ ] Configure inter-node TLS encryption (ClickHouse `<interserver_https_port>`)
- [ ] Set up automated backups (see Operations section)
- [ ] Configure log aggregation (ELK, Loki, etc.)
- [ ] Set up alerting rules in Prometheus (query failures, disk space, replication lag)
- [ ] Rotate credentials regularly
- [ ] Restrict Docker host access (firewall rules)
- [ ] Enable audit logging in ClickHouse

---

## Troubleshooting

### Container Issues

```bash
# Check container status
docker-compose ps

# View logs (all services)
docker-compose logs -f

# View logs (specific service)
docker-compose logs -f clickhouse-01
docker-compose logs --tail=100 clickhouse-keeper-01

# Restart service
docker-compose restart clickhouse-01
```

### Cluster Health

```bash
# Replication status
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "SELECT database, table, is_leader, is_readonly, total_replicas, active_replicas 
   FROM system.replicas"

# Replication queue (should be empty)
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "SELECT database, table, type, postpone_reason, last_exception 
   FROM system.replication_queue"

# Check Keeper quorum
for i in {01..03}; do
  echo "keeper-$i:"
  echo "mntr" | docker exec -i clickhouse-keeper-$i nc 127.0.0.1 9181 | grep zk_server_state
done
```

### Connection Issues

```bash
# Test direct node access
curl http://localhost:18123/ping  # Node 1
curl http://localhost:28123/ping  # Node 2
curl http://localhost:38123/ping  # Node 3
curl http://localhost:48123/ping  # Node 4

# Test load balancer
curl http://localhost:8123/ping

# Check HAProxy backend health
curl http://admin:YOUR_PASSWORD@localhost:8404
```

### Performance Issues

```bash
# View running queries
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "SELECT query_id, user, query, elapsed 
   FROM system.processes 
   ORDER BY elapsed DESC"

# Kill slow query
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "KILL QUERY WHERE query_id = 'query-id-here'"

# Check disk usage
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "SELECT name, path, formatReadableSize(free_space) as free, 
          formatReadableSize(total_space) as total 
   FROM system.disks"

# Check part count (high part count = merge backlog)
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD --query \
  "SELECT database, table, count() as parts 
   FROM system.parts 
   WHERE active 
   GROUP BY database, table 
   ORDER BY parts DESC"
```

---

## Operations

### Stop the Cluster

```bash
# Stop all services (keeps data)
docker-compose down

# Stop specific profile
docker-compose --profile monitoring down
```

### Backup

```bash
# Backup single node
docker run --rm \
  -v clickhouse-01-data:/source:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/clickhouse-01-$(date +%Y%m%d).tar.gz -C /source .

# Backup all nodes
for vol in clickhouse-{01..04}-data clickhouse-keeper-{01..03}-data; do
  docker run --rm \
    -v $vol:/source:ro \
    -v $(pwd)/backups:/backup \
    alpine tar czf /backup/${vol}-$(date +%Y%m%d).tar.gz -C /source .
done
```

**Better approach:** Use ClickHouse native backups:
```sql
-- Create backup to disk
BACKUP DATABASE my_db TO Disk('backups', 'backup-2026-06-28.zip');

-- Restore from backup
RESTORE DATABASE my_db FROM Disk('backups', 'backup-2026-06-28.zip');
```

### Restore

```bash
docker run --rm \
  -v clickhouse-01-data:/target \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/clickhouse-01-20260628.tar.gz -C /target
```

### Upgrade ClickHouse Version

```bash
# 1. Edit docker-compose.yml
# Change: image: "clickhouse/clickhouse-server:latest"
# To:     image: "clickhouse/clickhouse-server:24.6"

# 2. Pull new image
docker-compose pull

# 3. Recreate containers (data persists in volumes)
docker-compose up -d

# 4. Verify version
docker exec clickhouse-01 clickhouse-client --query "SELECT version()"
```

### Scale the Cluster

To add more shards/replicas:

1. Update `docker-compose.yml` with new node definitions
2. Update `setup.sh` to generate configs for new nodes
3. Run `./setup.sh` to regenerate configs
4. Update cluster definition in all nodes' config files
5. Start new nodes: `docker-compose up -d`
6. Verify: `SELECT * FROM system.clusters WHERE cluster = 'my_cluster'`

### Complete Cleanup (DESTRUCTIVE)

```bash
# Stop and remove all data
docker-compose down -v

# Remove generated configs
rm -rf fs/ grafana/provisioning/ prometheus.yml haproxy-*.cfg

# Remove credentials
rm -f .env .credentials

# Remove certificates
rm -rf certs/
```

---

## Configuration Files

### Directory Structure

```
.
├── docker-compose.yml          # Container orchestration
├── generate-env.sh             # Credential generator
├── setup.sh                    # Config generator
├── generate-certs.sh           # TLS certificate generator
├── .env.example                # Template for .env
├── README.md                   # This file
│
├── .env                        # Generated: environment variables (gitignored)
├── .credentials                # Generated: plain-text passwords (gitignored)
├── prometheus.yml              # Generated: Prometheus config (gitignored)
├── haproxy-http.cfg            # Generated: HTTP load balancer (gitignored)
├── haproxy-https.cfg           # Generated: HTTPS load balancer (gitignored)
│
├── fs/volumes/                 # Generated: ClickHouse configs (gitignored)
│   ├── clickhouse-01/etc/clickhouse-server/
│   │   ├── config.d/config.xml
│   │   └── users.d/users.xml
│   ├── clickhouse-02/...
│   ├── clickhouse-03/...
│   ├── clickhouse-04/...
│   ├── clickhouse-keeper-01/etc/clickhouse-keeper/keeper_config.xml
│   ├── clickhouse-keeper-02/...
│   └── clickhouse-keeper-03/...
│
├── grafana/provisioning/       # Generated: Grafana datasources (gitignored)
└── certs/                      # Generated: TLS certificates (gitignored)
```

### Modifying Configuration

**To change passwords:**
```bash
./generate-env.sh  # Regenerate .env
./setup.sh         # Regenerate configs with new hashes
docker-compose down
docker-compose --profile basic --profile loadbalancer up -d
```

**To reload config without restart:**
```bash
# Edit config in fs/volumes/clickhouse-01/...
docker exec clickhouse-01 clickhouse-client --user admin --password YOUR_PASSWORD \
  --query "SYSTEM RELOAD CONFIG"
```

**To completely regenerate:**
```bash
rm -rf fs/ grafana/provisioning/ prometheus.yml haproxy-*.cfg
./setup.sh
docker-compose down
docker-compose --profile basic --profile loadbalancer up -d
```

---

## Data Persistence

All data is stored in Docker named volumes (survives container recreation):

| Volume | Purpose |
|--------|---------|
| `clickhouse-01-data` through `clickhouse-04-data` | ClickHouse data, logs, access control |
| `clickhouse-keeper-01-data` through `clickhouse-keeper-03-data` | Keeper coordination state |
| `prometheus-data` | Prometheus metrics |
| `grafana-data` | Grafana dashboards and settings |

**To completely reset:**
```bash
docker-compose down -v  # ⚠️ DELETES ALL DATA
```

---

## References

- **ClickHouse Documentation:** https://clickhouse.com/docs
- **ClickHouse Deployment Guide:** https://clickhouse.com/docs/architecture/cluster-deployment
- **ClickHouse GitHub:** https://github.com/ClickHouse/ClickHouse
- **HAProxy Documentation:** https://www.haproxy.com/documentation/
- **Community Slack:** https://clickhouse.com/slack

---

## License

This is a development/testing setup. Review ClickHouse licensing and resource requirements before production deployment.
