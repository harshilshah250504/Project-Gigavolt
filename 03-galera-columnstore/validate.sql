SET SESSION wsrep_sync_wait=1;
SHOW GLOBAL STATUS WHERE Variable_name IN (
 'wsrep_cluster_size', 'wsrep_cluster_status',
 'wsrep_local_state_comment', 'wsrep_ready');
SELECT * FROM gigavolt_validation.replication_test ORDER BY id;

-- Run on Nodes 2 and 3; expected result is no rows.
SELECT TABLE_SCHEMA, TABLE_NAME, ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='gigavolt_benchmark';
