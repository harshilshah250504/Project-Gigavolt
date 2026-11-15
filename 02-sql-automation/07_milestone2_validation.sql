-- PROJECT GIGAVOLT - MILESTONE 2
-- FINAL VALIDATION SCRIPT

USE gigavolt;

-- 1. Generated column
DESCRIBE silver_dispatches;
SELECT dispatch_id, full_service_context
FROM silver_dispatches
LIMIT 5;

-- 2. Stored procedure exists and executes
SHOW PROCEDURE STATUS
WHERE Db = 'gigavolt'
  AND Name = 'sp_Prepare_RAG_Payloads';

CALL sp_Prepare_RAG_Payloads();

-- 3. RAG payloads
SELECT COUNT(*) AS total_rag_payloads
FROM rag_payloads;

SELECT
    payload_id,
    dispatch_id,
    equipment_id,
    customer_id,
    payload_text,
    created_at
FROM rag_payloads
LIMIT 5;

-- 4. Required service audit triggers
SHOW TRIGGERS LIKE 'silver_dispatches';

-- 5. Audit history
SELECT
    audit_id,
    audit_timestamp,
    database_user,
    table_name,
    operation_type,
    record_id,
    old_values,
    new_values,
    description
FROM Audit_Logs
ORDER BY audit_id;

-- 6. Audit immutability controls
SHOW TRIGGERS LIKE 'Audit_Logs';

-- 7. Security views
SHOW FULL TABLES
WHERE Table_type = 'VIEW';

SELECT *
FROM vw_customer_public
LIMIT 5;

DESCRIBE silver_customers;

SELECT *
FROM vw_service_rag_secure
LIMIT 5;

-- 8. Final row-count integrity check
SELECT 'silver_customers' AS table_name, COUNT(*) AS row_count
FROM silver_customers
UNION ALL
SELECT 'silver_equipment', COUNT(*) FROM silver_equipment
UNION ALL
SELECT 'silver_dispatches', COUNT(*) FROM silver_dispatches
UNION ALL
SELECT 'silver_parts', COUNT(*) FROM silver_parts
UNION ALL
SELECT 'silver_warranty_claims', COUNT(*) FROM silver_warranty_claims
UNION ALL
SELECT 'rag_payloads', COUNT(*) FROM rag_payloads
UNION ALL
SELECT 'Audit_Logs', COUNT(*) FROM Audit_Logs;

-- MANUAL IMMUTABILITY TESTS (run separately; errors are expected)
-- UPDATE Audit_Logs
-- SET description = 'Unauthorized modification'
-- WHERE audit_id = 1;
--
-- DELETE FROM Audit_Logs
-- WHERE audit_id = 1;
