-- PROJECT GIGAVOLT - MILESTONE 2
-- 3B/3C. REQUIRED AUDIT TRIGGERS

USE gigavolt;

DELIMITER $$

CREATE TRIGGER trg_dispatch_before_update
BEFORE UPDATE ON silver_dispatches
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (
        database_user, table_name, operation_type, record_id,
        old_values, new_values, description
    )
    VALUES (
        CURRENT_USER(),
        'silver_dispatches',
        'UPDATE',
        OLD.dispatch_id,
        CONCAT(
            'Technician: ', COALESCE(OLD.technician, 'NULL'),
            ' | Service Type: ', COALESCE(OLD.service_type, 'NULL'),
            ' | Resolution: ', COALESCE(OLD.resolution_summary, 'NULL'),
            ' | Status: ', COALESCE(OLD.status, 'NULL')
        ),
        CONCAT(
            'Technician: ', COALESCE(NEW.technician, 'NULL'),
            ' | Service Type: ', COALESCE(NEW.service_type, 'NULL'),
            ' | Resolution: ', COALESCE(NEW.resolution_summary, 'NULL'),
            ' | Status: ', COALESCE(NEW.status, 'NULL')
        ),
        CONCAT('Service record ', OLD.dispatch_id, ' updated')
    );
END$$

CREATE TRIGGER trg_dispatch_after_insert
AFTER INSERT ON silver_dispatches
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (
        database_user, table_name, operation_type, record_id,
        old_values, new_values, description
    )
    VALUES (
        CURRENT_USER(),
        'silver_dispatches',
        'INSERT',
        NEW.dispatch_id,
        NULL,
        CONCAT(
            'Equipment ID: ', COALESCE(NEW.equipment_id, 'NULL'),
            ' | Technician: ', COALESCE(NEW.technician, 'NULL'),
            ' | Service Type: ', COALESCE(NEW.service_type, 'NULL'),
            ' | Resolution: ', COALESCE(NEW.resolution_summary, 'NULL'),
            ' | Status: ', COALESCE(NEW.status, 'NULL')
        ),
        CONCAT('New service record ', NEW.dispatch_id, ' created')
    );
END$$

DELIMITER ;
