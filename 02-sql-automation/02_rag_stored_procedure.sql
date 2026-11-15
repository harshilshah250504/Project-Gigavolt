-- PROJECT GIGAVOLT - MILESTONE 2
-- 2. STORED PROCEDURE / MATERIALIZED RAG PREPARATION LAYER
-- Purpose: Build structured service payloads for downstream embedding/RAG.
-- Note: MariaDB does not use a native materialized-view object here;
-- rag_payloads is a persisted preparation layer refreshed by the procedure.

USE gigavolt;

CREATE TABLE rag_payloads (
    payload_id INT AUTO_INCREMENT PRIMARY KEY,
    dispatch_id VARCHAR(50) NOT NULL,
    equipment_id VARCHAR(50) NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    payload_text TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rag_dispatch
        FOREIGN KEY (dispatch_id) REFERENCES silver_dispatches(dispatch_id),
    CONSTRAINT fk_rag_equipment
        FOREIGN KEY (equipment_id) REFERENCES silver_equipment(equipment_id),
    CONSTRAINT fk_rag_customer
        FOREIGN KEY (customer_id) REFERENCES silver_customers(customer_id)
);

DELIMITER $$

CREATE PROCEDURE sp_Prepare_RAG_Payloads()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    DELETE FROM rag_payloads;

    INSERT INTO rag_payloads (
        dispatch_id,
        equipment_id,
        customer_id,
        payload_text
    )
    SELECT
        d.dispatch_id,
        d.equipment_id,
        e.customer_id,
        CONCAT(
            'Equipment Model: ', COALESCE(e.model, 'N/A'),
            ' | ', d.full_service_context,
            ' | Location Notes: ', COALESCE(e.location_notes, 'No location notes')
        )
    FROM silver_dispatches d
    INNER JOIN silver_equipment e
        ON d.equipment_id = e.equipment_id;

    COMMIT;
END$$

DELIMITER ;
