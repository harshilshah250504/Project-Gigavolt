-- PROJECT GIGAVOLT - MILESTONE 2
-- 3D. AUDIT LOG IMMUTABILITY CONTROLS

USE gigavolt;

DELIMITER $$

CREATE TRIGGER trg_audit_prevent_update
BEFORE UPDATE ON Audit_Logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Audit records are immutable and cannot be updated';
END$$

CREATE TRIGGER trg_audit_prevent_delete
BEFORE DELETE ON Audit_Logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Audit records are immutable and cannot be deleted';
END$$

DELIMITER ;
