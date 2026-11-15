USE gigavolt;
CREATE TABLE mv_service_analytics (
 payload_id INT NOT NULL PRIMARY KEY,
 dispatch_id VARCHAR(50) NOT NULL,
 equipment_id VARCHAR(50) NOT NULL,
 customer_id VARCHAR(50) NOT NULL,
 dispatch_date DATE NOT NULL,
 service_type VARCHAR(100) NOT NULL,
 hours_spent DECIMAL(10,2) NOT NULL,
 labor_cost DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;

INSERT INTO mv_service_analytics
SELECT r.payload_id, r.dispatch_id, r.equipment_id, r.customer_id,
       d.dispatch_date, d.service_type, d.hours_spent, d.labor_cost
FROM rag_payloads AS r
JOIN silver_dispatches AS d ON d.dispatch_id=r.dispatch_id;

SET SESSION wsrep_on=OFF;
SET SESSION wsrep_OSU_method='RSU';
SET SESSION columnstore_select_handler=OFF;
CREATE DATABASE gigavolt_benchmark;
CREATE TABLE gigavolt_benchmark.analytics_innodb (
 payload_id INT NOT NULL,
 dispatch_id VARCHAR(50) NOT NULL,
 equipment_id VARCHAR(50) NOT NULL,
 customer_id VARCHAR(50) NOT NULL,
 dispatch_date DATE NOT NULL,
 service_type VARCHAR(100) NOT NULL,
 hours_spent DECIMAL(10,2) NOT NULL,
 labor_cost DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;
INSERT INTO gigavolt_benchmark.analytics_innodb
SELECT payload_id, dispatch_id, equipment_id, customer_id,
       dispatch_date, service_type, hours_spent, labor_cost
FROM gigavolt.mv_service_analytics;
CREATE TABLE gigavolt_benchmark.analytics_columnstore (
 payload_id INT NOT NULL,
 dispatch_id VARCHAR(50) NOT NULL,
 equipment_id VARCHAR(50) NOT NULL,
 customer_id VARCHAR(50) NOT NULL,
 dispatch_date DATE NOT NULL,
 service_type VARCHAR(100) NOT NULL,
 hours_spent DECIMAL(10,2) NOT NULL,
 labor_cost DECIMAL(12,2) NOT NULL
) ENGINE=ColumnStore;
INSERT INTO gigavolt_benchmark.analytics_columnstore
SELECT payload_id, dispatch_id, equipment_id, customer_id,
       dispatch_date, service_type, hours_spent, labor_cost
FROM gigavolt.mv_service_analytics;
