# GitHub Actions CI/CD

## Workflows

### `ci.yml` - ClickHouse Cluster CI

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

**What It Tests:**

#### Job 1: `test-cluster` (Full Stack Test)
1. **Setup**: Generates `.env` and configs non-interactively
2. **Configuration**: Verifies all config files generated correctly
3. **Services**: Starts all services (ClickHouse, Keeper, HAProxy, Prometheus, Grafana)
4. **Keeper Quorum**: Tests 3-node Keeper cluster quorum
5. **Node Connectivity**: Tests all 4 ClickHouse nodes individually
6. **Load Balancer**: Tests HAProxy HTTP endpoint and stats page
7. **Cluster Topology**: Verifies `my_cluster` with 2 shards × 2 replicas
8. **Database Operations**:
   - Creates database with `ON CLUSTER my_cluster`
   - Creates replicated table
   - Creates distributed table
   - Inserts data
   - Queries data
   - Verifies data distribution across shards
9. **Replication**: Checks replication status and active replicas
10. **Monitoring**:
    - Tests Prometheus health and metrics endpoints
    - Tests Grafana health and datasource configuration
11. **Health Check**: Runs comprehensive cluster verification
12. **Cleanup**: Removes all containers and volumes

**Duration**: ~10-12 minutes

#### Job 2: `test-tls` (TLS Configuration Test)
1. **Setup**: Generates configs and TLS certificates
2. **Certificates**: Verifies cert files created
3. **Services**: Starts cluster with HTTPS profile
4. **HTTPS**: Tests HTTPS endpoint (8443) and HTTPS stats (8405)
5. **Cleanup**: Removes all containers and volumes

**Duration**: ~6-8 minutes

**Note**: Runs sequentially after `test-cluster` completes to avoid container name conflicts (both jobs use `clickhouse-loadbalancer`, etc.)

---

## Test Credentials (CI Only)

**⚠️ These are hardcoded for CI testing only - NEVER use in production!**

```
ClickHouse Admin:
  Username: admin
  Password: test_admin_password_12345

ClickHouse App User:
  Username: app_user
  Password: test_app_user_password_12345

Grafana:
  Username: admin
  Password: test_grafana_password_12345

HAProxy Stats:
  Username: admin
  Password: test_haproxy_password_12345
```

---

## Viewing CI Results

**GitHub UI:**
1. Go to "Actions" tab in GitHub repository
2. Click on latest workflow run
3. Expand job steps to see detailed logs

**Badge Status:**
- ✅ Green: All tests passing
- ❌ Red: Tests failing (check logs)
- 🟡 Yellow: Tests running

---

## Running Locally (Same as CI)

```bash
# Generate .env with test credentials
cat > .env << EOF
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=test_grafana_password_12345
GF_SECURITY_SECRET_KEY=test_secret_key_abcdefghijklmnopqrstuvwxyz12345
CLICKHOUSE_ADMIN_PASSWORD_SHA256=$(echo -n "test_admin_password_12345" | sha256sum | awk '{print $1}')
CLICKHOUSE_APP_USER_PASSWORD_SHA256=$(echo -n "test_app_user_password_12345" | sha256sum | awk '{print $1}')
HAPROXY_STATS_USER=admin
HAPROXY_STATS_PASSWORD=test_haproxy_password_12345
EOF

# Generate configs
./setup.sh

# Start cluster
docker compose --profile basic --profile loadbalancer --profile monitoring up -d

# Wait and verify
sleep 60
./verify-cluster.sh
```

---

## Actions Used (Latest Versions)

| Action | Version | Purpose |
|--------|---------|---------|
| `actions/checkout` | v4 | Checkout repository code |
| `docker/setup-buildx-action` | v3 | Set up Docker Buildx for multi-platform builds |

**Update Schedule**: Actions are pinned to major versions (`@v4`, `@v3`) to receive patch updates automatically while preventing breaking changes.

---

## Troubleshooting CI Failures

### Keeper Not Starting
- **Symptom**: Keeper health checks timeout
- **Check**: Keeper logs in "Display service logs on failure" step
- **Fix**: Usually timing issue, workflow waits 60s + retries

### ClickHouse Not Starting
- **Symptom**: Node connectivity tests fail
- **Check**: ClickHouse logs for config errors
- **Fix**: Verify `setup.sh` generates valid XML configs

### Replication Not Working
- **Symptom**: `active_replicas` != 2
- **Check**: Keeper quorum status, ClickHouse logs
- **Fix**: Usually Keeper coordination delay, increase wait time

### Prometheus/Grafana Timeout
- **Symptom**: Monitoring tests fail
- **Check**: Container memory limits (CI runners have limited resources)
- **Fix**: Reduce test scope or increase timeouts

### Port Conflicts
- **Symptom**: Services fail to bind to ports
- **Check**: GitHub runner already has services on those ports
- **Fix**: Use different ports or stop conflicting services

---

## CI Performance

**Resource Usage (per run):**
- CPU: ~2 cores
- Memory: ~4GB
- Disk: ~2GB
- Network: ~500MB (Docker image pulls)

**GitHub Actions Limits:**
- Free tier: 2,000 minutes/month (public repos get unlimited)
- Runner specs: 2-core CPU, 7GB RAM, 14GB SSD

---

## Future Enhancements

Potential additions to CI pipeline:

- [ ] Performance benchmarks (insert/query throughput)
- [ ] Stress testing (high concurrent queries)
- [ ] Backup/restore testing
- [ ] Upgrade testing (test version upgrades)
- [ ] Security scanning (Trivy, Snyk)
- [ ] Multi-platform testing (arm64)
- [ ] Chaos testing (kill random nodes, verify recovery)
- [ ] Query correctness tests (compare results across shards)

---

## Manual Workflow Dispatch

Trigger CI manually from GitHub UI:

1. Go to "Actions" tab
2. Select "ClickHouse Cluster CI" workflow
3. Click "Run workflow"
4. Select branch
5. Click "Run workflow" button

Useful for testing before merging PRs.
