# GitHub Actions CI Pipeline Overview

## 🎯 What Gets Tested

The CI pipeline comprehensively tests the entire ClickHouse cluster setup automatically on every push and PR.

### Test Coverage

**✅ Configuration Generation**
- `.env` file with SHA256 password hashes
- 4 ClickHouse server configs
- 3 ClickHouse Keeper configs
- HAProxy HTTP and HTTPS configs
- Prometheus and Grafana configs

**✅ Service Health**
- All Docker containers start successfully
- Health checks pass for all services
- Services respond on correct ports

**✅ ClickHouse Keeper**
- 3-node quorum established
- Leader election works
- Follower nodes respond

**✅ ClickHouse Nodes**
- All 4 nodes respond on HTTP interface
- Direct node access works (ports 18123, 28123, 38123, 48123)
- Native protocol accessible

**✅ Load Balancer**
- HAProxy distributes requests
- HTTP endpoint works (port 8123)
- HTTPS endpoint works (port 8443)
- Stats page accessible (ports 8404, 8405)

**✅ Cluster Topology**
- `my_cluster` configured correctly
- 2 shards × 2 replicas visible
- All nodes in system.clusters

**✅ Database Operations**
- `CREATE DATABASE ON CLUSTER` works
- `CREATE TABLE ON CLUSTER` works
- Replicated table creation succeeds
- Distributed table creation succeeds
- Data insertion works
- Data querying works
- Data distributed across shards

**✅ Replication**
- Replication configured correctly
- Active replicas = 2 per shard
- Replication queue healthy

**✅ Monitoring**
- Prometheus scrapes all targets
- Prometheus health endpoint responds
- ClickHouse metrics exposed
- Grafana health endpoint responds
- Grafana datasource configured

**✅ TLS/HTTPS**
- Certificate generation works
- HTTPS endpoint responds
- HTTPS stats page accessible
- TLS termination at HAProxy works

---

## 📊 CI Pipeline Structure

```
┌─────────────────────────────────────────────────────────┐
│                    Push/PR to main                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ├──────────────────┬─────────────────┐
                     ▼                  ▼                 ▼
            ┌────────────────┐  ┌──────────────┐  ┌──────────────┐
            │  Checkout Code │  │ Setup Docker │  │ Generate .env│
            └────────┬───────┘  └──────┬───────┘  └──────┬───────┘
                     │                  │                 │
                     └──────────────────┴─────────────────┘
                                        │
                     ┌──────────────────┴────────────────────┐
                     ▼                                       ▼
            ┌────────────────────┐                 ┌────────────────┐
            │   test-cluster     │                 │   test-tls     │
            │  (Full Stack)      │                 │  (HTTPS Only)  │
            └────────┬───────────┘                 └────────┬───────┘
                     │                                       │
            ┌────────┴────────┐                   ┌─────────┴────────┐
            ▼                 ▼                   ▼                  ▼
    ┌──────────────┐  ┌─────────────┐   ┌──────────────┐  ┌────────────┐
    │Start Services│  │Test Services│   │Generate Certs│  │Test HTTPS  │
    └──────┬───────┘  └─────┬───────┘   └──────┬───────┘  └─────┬──────┘
           │                │                   │                 │
           ▼                ▼                   ▼                 ▼
    ┌──────────────────────────────────────────────────────────────┐
    │  15 Test Steps (Keeper, Nodes, LB, Cluster, DB, Replication, │
    │  Monitoring) + HTTPS (4 Test Steps)                           │
    └──────────────────────────────────────────────────────────────┘
           │                                       │
           ▼                                       ▼
    ┌──────────────┐                       ┌──────────────┐
    │   Cleanup    │                       │   Cleanup    │
    └──────────────┘                       └──────────────┘
```

---

## ⏱️ Timing

**Total CI Duration**: ~15-18 minutes

| Job | Duration | Steps |
|-----|----------|-------|
| `test-cluster` | 10-12 min | 15 test steps |
| `test-tls` | 6-8 min | 4 test steps |

**Breakdown (test-cluster):**
- Setup & config generation: 1 min
- Service startup: 1 min
- Wait for healthy: 1 min
- Keeper tests: 1 min
- Node connectivity: 2 min
- Database operations: 3 min
- Replication checks: 1 min
- Monitoring tests: 2 min

---

## 🔍 What Each Job Tests

### Job 1: `test-cluster` (Full Stack)

**Purpose**: Verify entire cluster works end-to-end with monitoring

**Profiles**: `basic`, `loadbalancer`, `monitoring`

**Tests**:
1. ✅ Config generation (setup.sh)
2. ✅ All 13 config files exist
3. ✅ Docker Compose starts all services
4. ✅ 3 Keeper nodes form quorum
5. ✅ 4 ClickHouse nodes respond
6. ✅ HAProxy load balances requests
7. ✅ Cluster topology is correct (2x2)
8. ✅ CREATE DATABASE ON CLUSTER works
9. ✅ CREATE TABLE ON CLUSTER works
10. ✅ INSERT data works
11. ✅ SELECT data works
12. ✅ Data distributed across shards
13. ✅ Replication active (2 replicas/shard)
14. ✅ Prometheus scrapes metrics
15. ✅ Grafana datasource configured

**On Failure**: Displays logs from failed services

### Job 2: `test-tls` (HTTPS)

**Purpose**: Verify TLS/HTTPS configuration works

**Profiles**: `basic`, `tls`

**Tests**:
1. ✅ generate-certs.sh creates certificates
2. ✅ server.pem, server.crt, server.key exist
3. ✅ HAProxy starts with TLS profile
4. ✅ HTTPS endpoint responds (8443)
5. ✅ HTTPS stats page works (8405)

---

## 🚀 Running CI Locally

Replicate CI environment locally:

```bash
# Use CI test credentials
cat > .env << EOF
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=test_grafana_password_12345
GF_SECURITY_SECRET_KEY=test_secret_key_abcdefghijklmnopqrstuvwxyz12345
CLICKHOUSE_ADMIN_PASSWORD_SHA256=$(echo -n "test_admin_password_12345" | sha256sum | awk '{print $1}')
CLICKHOUSE_APP_USER_PASSWORD_SHA256=$(echo -n "test_app_user_password_12345" | sha256sum | awk '{print $1}')
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=test_haproxy_password_12345
