-- PROJECT GIGAVOLT - MILESTONE 2
-- 1. VIRTUAL / GENERATED COLUMN
-- Purpose: Dynamically combine service information into a structured
-- text field suitable for downstream RAG processing.

USE gigavolt;

ALTER TABLE silver_dispatches
ADD COLUMN full_service_context TEXT
GENERATED ALWAYS AS (
    CONCAT(
        'Dispatch ID: ', COALESCE(dispatch_id, 'N/A'),
        ' | Equipment ID: ', COALESCE(equipment_id, 'N/A'),
        ' | Service Date: ', COALESCE(DATE_FORMAT(dispatch_date, '%Y-%m-%d'), 'N/A'),
        ' | Technician: ', COALESCE(technician, 'N/A'),
        ' | Service Type: ', COALESCE(service_type, 'N/A'),
        ' | Resolution: ', COALESCE(resolution_summary, 'No resolution provided'),
        ' | Status: ', COALESCE(status, 'N/A')
    )
) VIRTUAL;
