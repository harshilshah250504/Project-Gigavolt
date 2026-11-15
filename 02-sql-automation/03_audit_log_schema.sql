-- PROJECT GIGAVOLT - MILESTONE 2
-- 3A. AUDIT LOG SCHEMA
-- Purpose: Maintain a historical record of important database changes.

USE gigavolt;

CREATE TABLE Audit_Logs (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    audit_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    database_user VARCHAR(255) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation_type VARCHAR(20) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    old_values TEXT,
    new_values TEXT,
    description VARCHAR(500)
);
