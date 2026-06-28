-- ============================================
-- ClickHouse Cluster - Test SQL Statements
-- ============================================
-- This file contains all SQL statements needed for testing distributed tables
-- Each section can be executed independently or sourced by scripts
--
-- Usage:
--   Run entire file: clickhouse-client --user admin --password XXX --multiquery < test_sql.sql
--   Run specific section: Extract section and run separately
--
-- Sections:
--   1. DATABASE_SETUP - Create database
--   2. TABLE_CREATION - Create local and distributed tables
--   3. DATA_INSERT - Insert test data
--   4. DATA_QUERY - Query and verify data
--   5. CLUSTER_VERIFICATION - Check cluster status
--   6. CLEANUP - Remove test data and tables
-- ============================================

-- ============================================
-- SECTION: DATABASE_SETUP
-- Create the database on all cluster nodes
-- ============================================
CREATE DATABASE IF NOT EXISTS test_db ON CLUSTER my_cluster;

-- Verify database exists on all nodes
SELECT
    hostName() as node,
    name as database
FROM clusterAllReplicas('my_cluster', system.databases)
WHERE name = 'test_db'
ORDER BY node;

-- ============================================
-- SECTION: TABLE_CREATION
-- Create local replicated table and distributed table
-- ============================================

-- Step 1: Create local replicated table on all nodes
-- This table stores the actual data and auto-replicates within each shard
CREATE TABLE IF NOT EXISTS test_db.test_table ON CLUSTER my_cluster
(
    id UInt32,
    name String,
    created_at DateTime DEFAULT now(),
    description String DEFAULT ''
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{database}/{table}/{shard}', '{replica}')
ORDER BY id;

-- Step 2: Create distributed table on all nodes
-- This is the query interface that routes requests to all shards
CREATE TABLE IF NOT EXISTS test_db.test_table_distributed ON CLUSTER my_cluster
AS test_db.test_table
ENGINE = Distributed('my_cluster', 'test_db', 'test_table', rand());

-- Verify tables exist on all nodes
SELECT
    hostName() as node,
    database,
    name as table_name,
    engine
FROM clusterAllReplicas('my_cluster', system.tables)
WHERE database = 'test_db'
ORDER BY node, table_name;

-- ============================================
-- SECTION: DATA_INSERT
-- Insert test data via distributed table
-- ============================================

-- Insert sample data
-- The distributed engine will automatically shard data across nodes
INSERT INTO test_db.test_table_distributed (id, name, description) VALUES
    (1, 'test1', 'First test record'),
    (2, 'test2', 'Second test record'),
    (3, 'test3', 'Third test record'),
    (4, 'test4', 'Fourth test record'),
    (5, 'test5', 'Fifth test record');

-- Insert integration test data (for automated testing)
INSERT INTO test_db.test_table_distributed (id, name, description) VALUES
    (100, 'integration_test_1', 'Integration test record 1'),
    (200, 'integration_test_2', 'Integration test record 2');

-- ============================================
-- SECTION: DATA_QUERY
-- Query and verify data distribution
-- ============================================

-- Query 1: Select all data from distributed table
SELECT
    id,
    name,
    description,
    created_at
FROM test_db.test_table_distributed
ORDER BY id;

-- Query 2: Count total rows
SELECT count() as total_rows
FROM test_db.test_table_distributed;

-- Query 3: Query integration test data only
SELECT
    id,
    name,
    description
FROM test_db.test_table_distributed
WHERE name LIKE 'integration_test%'
ORDER BY id;

-- Query 4: Count integration test rows
SELECT count() as integration_test_rows
FROM test_db.test_table_distributed
WHERE name LIKE 'integration_test%';

-- Query 5: Group by and aggregate
SELECT
    toYYYYMM(created_at) as month,
    count() as row_count
FROM test_db.test_table_distributed
GROUP BY month
ORDER BY month;

-- ============================================
-- SECTION: CLUSTER_VERIFICATION
-- Verify cluster topology and data distribution
-- ============================================

-- Check cluster topology
SELECT
    cluster,
    shard_num,
    replica_num,
    host_name,
    host_address,
    port
FROM system.clusters
WHERE cluster = 'my_cluster'
ORDER BY shard_num, replica_num;

-- Check data distribution across all nodes
SELECT
    hostName() as node,
    count() as row_count,
    groupArray(id) as ids
FROM clusterAllReplicas('my_cluster', test_db.test_table)
GROUP BY node
ORDER BY node;

-- Check replication status
SELECT
    database,
    table,
    is_leader,
    total_replicas,
    active_replicas,
    is_readonly,
    zookeeper_path
FROM system.replicas
WHERE database = 'test_db';

-- Check integration test data distribution per node
SELECT
    hostName() as node,
    count() as test_row_count
FROM clusterAllReplicas('my_cluster', test_db.test_table)
WHERE name LIKE 'integration_test%'
GROUP BY node
ORDER BY node;

-- ============================================
-- SECTION: CLEANUP
-- Clean up test data and tables
-- ============================================

-- Option 1: Delete specific test data (mutation - async)
ALTER TABLE test_db.test_table ON CLUSTER my_cluster
DELETE WHERE name LIKE 'integration_test%';

-- Option 2: Drop tables (immediate)
DROP TABLE IF EXISTS test_db.test_table_distributed ON CLUSTER my_cluster;
DROP TABLE IF EXISTS test_db.test_table ON CLUSTER my_cluster;

-- Option 3: Drop entire database (immediate)
DROP DATABASE IF EXISTS test_db ON CLUSTER my_cluster;

-- Verify cleanup
SELECT
    hostName() as node,
    name as database
FROM clusterAllReplicas('my_cluster', system.databases)
WHERE name = 'test_db'
ORDER BY node;

-- ============================================
-- SECTION: ADVANCED_QUERIES
-- Advanced query examples for reference
-- ============================================

-- Query data from specific shard only
SELECT
    id,
    name,
    _shard_num
FROM cluster('my_cluster', test_db.test_table)
WHERE _shard_num = 1
ORDER BY id;

-- Check which shard each row is stored in
SELECT
    id,
    name,
    hostName() as stored_on_node
FROM test_db.test_table_distributed
ORDER BY id;

-- Aggregate query across shards
SELECT
    count() as total_rows,
    min(id) as min_id,
    max(id) as max_id,
    avg(id) as avg_id
FROM test_db.test_table_distributed;

-- Join example (if you have multiple tables)
-- SELECT
--     t1.id,
--     t1.name,
--     t2.related_field
-- FROM test_db.test_table_distributed t1
-- JOIN test_db.other_table_distributed t2 ON t1.id = t2.id;

-- ============================================
-- SECTION: TROUBLESHOOTING
-- Diagnostic queries for troubleshooting
-- ============================================

-- Check if database exists on all nodes
SELECT
    hostName() as node,
    count() as databases_named_test_db
FROM clusterAllReplicas('my_cluster', system.databases)
WHERE name = 'test_db'
GROUP BY node
ORDER BY node;

-- Check table engines on all nodes
SELECT
    hostName() as node,
    name as table_name,
    engine,
    engine_full
FROM clusterAllReplicas('my_cluster', system.tables)
WHERE database = 'test_db'
ORDER BY node, table_name;

-- Check for errors in replication queue
SELECT
    database,
    table,
    replica_name,
    position,
    type,
    create_time,
    is_currently_executing,
    num_tries,
    last_exception
FROM system.replication_queue
WHERE database = 'test_db' AND num_tries > 0;

-- Check Keeper/ZooKeeper connection
SELECT
    name,
    value
FROM system.zookeeper
WHERE path = '/clickhouse'
LIMIT 10;

-- ============================================
-- END OF SQL FILE
-- ============================================
