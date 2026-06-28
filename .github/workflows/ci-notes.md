# CI Pipeline Design Notes

## Sequential Execution (Not Parallel)

The CI pipeline runs jobs **sequentially**, not in parallel:

```yaml
test-tls:
  needs: test-cluster  # Waits for test-cluster to complete
```

### Why?

Both jobs use the same Docker container names:
- `clickhouse-loadbalancer`
- `clickhouse-01`, `clickhouse-02`, `clickhouse-03`, `clickhouse-04`
- `clickhouse-keeper-01`, `clickhouse-keeper-02`, `clickhouse-keeper-03`
- `prometheus`
- `grafana`

Running in parallel would cause:
```
Error: container name "clickhouse-loadbalancer" is already in use
```

### Trade-offs

**Sequential (Current)**
- ✅ No container name conflicts
- ✅ Simple configuration
- ✅ Reliable cleanup between jobs
- ❌ Slower total time (~16-20 min vs ~10-12 min)

**Parallel (Alternative)**
- ✅ Faster total time
- ❌ Requires unique container names per job
- ❌ More complex docker-compose overrides
- ❌ Higher resource usage on CI runner

### Could We Run in Parallel?

Yes, but requires:

1. **Container name prefix per job:**
   ```yaml
   environment:
     COMPOSE_PROJECT_NAME: test-cluster-${{ github.run_id }}
   ```

2. **Different ports per job:**
   - Requires docker-compose override files
   - More complex configuration

3. **GitHub runner resource limits:**
   - 2 cores, 7GB RAM
   - Running 18 containers simultaneously might hit limits

**Decision**: Sequential execution is simpler and more reliable for this use case.

---

## Resource Usage

**Per Job:**
- Containers: 9 (test-cluster) or 7 (test-tls)
- Memory: ~3-4GB
- CPU: 2 cores
- Disk: ~1GB

**Sequential Benefits:**
- Each job gets full runner resources
- No resource contention
- Easier to debug failures

---

## Alternative Strategies Considered

### 1. Matrix Strategy
Run same tests across multiple configurations:
```yaml
strategy:
  matrix:
    profile: [http, https]
```
**Rejected**: Our tests are fundamentally different (full stack vs TLS only)

### 2. Conditional Jobs
Run TLS tests only on specific branches:
```yaml
if: github.ref == 'refs/heads/main'
```
**Rejected**: Want TLS tested on every PR

### 3. Single Job with Multiple Steps
Combine both jobs into one:
```yaml
- name: Test HTTP
- name: Test HTTPS
```
**Rejected**: Harder to see which test failed, no parallelism option in future

---

## Current Solution Summary

```yaml
jobs:
  test-cluster:
    # Full stack test (HTTP + monitoring)
    # Duration: 10-12 min

  test-tls:
    needs: test-cluster  # ← Sequential execution
    # TLS-specific test
    # Duration: 6-8 min
```

**Total**: 16-20 minutes (acceptable for comprehensive testing)
