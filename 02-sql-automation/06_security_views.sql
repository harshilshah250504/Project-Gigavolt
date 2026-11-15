-- PROJECT GIGAVOLT - MILESTONE 2
-- 4. DATA SECURITY VIEWS
-- Purpose: Expose only the fields needed for operational/RAG use.

USE gigavolt;

CREATE VIEW vw_customer_public AS
SELECT
    customer_id,
    company_name,
    city,
    state,
    country,
    status
FROM silver_customers;

CREATE VIEW vw_service_rag_secure AS
SELECT
    d.dispatch_id,
    d.equipment_id,
    e.model AS equipment_model,
    d.dispatch_date,
    d.technician,
    d.service_type,
    d.resolution_summary,
    d.status,
    d.full_service_context
FROM silver_dispatches d
INNER JOIN silver_equipment e
    ON d.equipment_id = e.equipment_id;
