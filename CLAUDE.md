# ClickHouse Cluster - Quick Reference

## What This Is
Production-ready ClickHouse cluster: 4 servers (2 shards × 2 replicas), 3 Keeper nodes, HAProxy load balancer, Prometheus + Grafana monitoring.

## Architecture
- **Cluster name**: `my_cluster` (used in all SQL: `ON CLUSTER my_cluster`)
- **Replication**: `internal_replication=true` (insert once, auto-replicate)
- **Coordination**: ClickHouse Keeper (not ZooKeeper)
- **Load balancing**: HAProxy round-robin across all 4 nodes

## File Organization

### Source Files (tracked in git)
```
docker-compose.yml          Container definitions, profiles control services
setup.sh                    Generates all configs from .env
generate-env.sh             Creates .env + .credentials with secure passwords
generate-certs.sh           Creates self-signed TLS certs for HAProxy
verify-cluster.sh           Automated health check
verify-security.sh          Security audit
.env.example                Template showing required variables
```

### Generated Files (gitignored, regenerate with setup.sh)
```
.env                        Credentials (SHA256 hashes for ClickHouse)
.credentials                Plain-text passwords (reference only)
fs/volumes/clickhouse-*/    ClickHouse server configs (4 nodes)
fs/volumes/keeper-*/        Keeper configs (3 nodes)
haproxy-http.cfg            HTTP load balancer config
haproxy-https.cfg           HTTPS load balancer config (TLS termination)
prometheus.yml              Metrics scraping config
grafana/provisioning/       Grafana datasource config
certs/                      TLS certificates (server.pem for HAProxy)
```

## Quick Answers

**Cluster name mismatch?** → Must be `my_cluster` everywhere (setup.sh line 98, README examples)

**Add/change passwords?** → Run `./generate-env.sh` then `./setup.sh` to regenerate configs

**Cluster won't start?** → Check `.env` exists, run `./setup.sh`, wait 30s after `docker-compose up`

**SQL not working?** → Always use `ON CLUSTER my_cluster` for DDL

**Change ClickHouse config?** → Edit setup.sh (generates to fs/volumes/), not fs/ directly

**Change HAProxy config?** → Edit setup.sh lines 293-443 (generates haproxy-*.cfg)

**Monitoring not showing?** → Start with `--profile monitoring`, check ports 9090 (Prometheus), 3000 (Grafana)

## Component Reasons

| Component | Why |
|-----------|-----|
| **ClickHouse Keeper** | Replaces ZooKeeper, native coordination, 3 nodes = quorum |
| **HAProxy** | TLS termination, load balancing, health checks, stats page |
| **Prometheus** | Scrapes ClickHouse `/metrics` endpoint (port 9363 per node) |
| **Grafana** | Visualizes Prometheus metrics, pre-configured datasource |
| **Docker profiles** | `basic` (required), `loadbalancer` (HTTP), `tls` (HTTPS), `monitoring` (Prom+Graf) |
| **SHA256 passwords** | ClickHouse security requirement (setup.sh reads from .env) |

## Port Map (127.0.0.1 only)

```
HAProxy:     8123 (HTTP), 8443 (HTTPS), 9000 (TCP), 8404 (stats)
CH-01:       18123 (HTTP), 19000 (TCP), 19363 (metrics)
CH-02:       28123, 29000, 29363
CH-03:       38123, 39000, 39363
CH-04:       48123, 49000, 49363
Keeper-01:   9181 (client), 19182 (metrics)
Keeper-02:   9182, 29182
Keeper-03:   9183, 39182
Prometheus:  9090
Grafana:     3000
```

## Key Patterns

**Create replicated table:**
```sql
-- Local table (auto-replicated within shard)
CREATE TABLE db.tbl ON CLUSTER my_cluster (...) 
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/{table}/{shard}', '{replica}')
ORDER BY ...;

-- Distributed table (query interface across shards)
CREATE TABLE db.tbl_distributed ON CLUSTER my_cluster AS db.tbl
ENGINE = Distributed('my_cluster', 'db', 'tbl', rand());
```

**Macros (auto-substituted per node):**
- `{database}` - database name
- `{table}` - table name
- `{shard}` - 01 or 02
- `{replica}` - 01 or 02

**ZooKeeper paths:**
- Must include `{shard}` for independent shard replication
- Format: `/clickhouse/tables/{database}/{table}/{shard}`

## Troubleshooting Lookup

| Issue | Check | Fix |
|-------|-------|-----|
| Containers not starting | `docker-compose ps` | `.env` missing → run `./generate-env.sh` |
| Cluster not visible | `SELECT * FROM system.clusters` | Wrong cluster name → ensure `my_cluster` |
| Replication not working | `SELECT * FROM system.replicas` | Check Keeper: `echo mntr \| nc localhost 9181` |
| Password auth failing | `.credentials` file | Re-run `./generate-env.sh` + `./setup.sh` |
| Load balancer down | `curl localhost:8123/ping` | Check HAProxy: `docker logs clickhouse-loadbalancer` |
| TLS not working | `certs/server.pem` exists? | Run `./generate-certs.sh` |
| High part count | `SELECT * FROM system.parts` | Merges slow, check disk/CPU, avoid `OPTIMIZE TABLE` |

## Development Workflow

```bash
# First time setup
./generate-env.sh      # Creates .env + .credentials
./setup.sh             # Generates all configs
docker-compose --profile basic --profile loadbalancer up -d
./verify-cluster.sh    # Automated health check

# After changing passwords
./generate-env.sh
./setup.sh
docker-compose down && docker-compose --profile basic --profile loadbalancer up -d

# After changing setup.sh
./setup.sh             # Regenerates configs
docker-compose restart # Or down/up for full restart
```

## Security Notes

- **Never commit**: `.env`, `.credentials`, `certs/`, `fs/` (all gitignored)
- **Passwords**: SHA256-hashed in ClickHouse, plain-text in `.credentials` for reference
- **Network**: All services bound to 127.0.0.1 (localhost only)
- **Users**: `admin` (full), `app_user` (limited), `default` (disabled)
- **Production**: Use vault for secrets, trusted CA certs, enable inter-node TLS

## When Editing

- **ClickHouse config** → Edit setup.sh (generates to fs/volumes/)
- **HAProxy config** → Edit setup.sh (generates haproxy-*.cfg)
- **Users/passwords** → Run generate-env.sh + setup.sh
- **Cluster topology** → Edit docker-compose.yml + setup.sh
- **Monitoring** → Edit setup.sh (prometheus.yml, grafana provisioning)

## Best Practices Applied

✅ `internal_replication=true` - Insert to one replica, auto-replicates  
✅ 3 Keeper nodes - Fault-tolerant quorum  
✅ `ON CLUSTER` for all DDL - Consistent schema across nodes  
✅ Distributed table sharding - `rand()` for even distribution  
✅ Resource limits - 300s query timeout, 10GB memory max  
✅ Query logging - `log_queries=1` in default profile  
✅ Health checks - All services have healthchecks in docker-compose  
✅ Monitoring - Prometheus scrapes all nodes + Keepers  

## Reference

**Official docs**: https://clickhouse.com/docs/architecture/cluster-deployment  
**Quick start**: See README.md (4-step process)  
**Full changes**: See CHANGES.md  
**Review summary**: See REVIEW_SUMMARY.md
