-- Historical coursework script. Run in a fresh gigavolt schema.
USE gigavolt;

#CREATE BRONZE TABLE
DROP TABLE IF EXISTS silver_customers;
DROP TABLE IF EXISTS bronze_customers;

CREATE TABLE bronze_customers (
    source_row_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id VARCHAR(50),
    company_name VARCHAR(255),
    contact_name VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    address VARCHAR(500),
    city VARCHAR(100),
    state VARCHAR(100),
    zip VARCHAR(50),
    country VARCHAR(100),
    created_date VARCHAR(100),
    status VARCHAR(50)
);

#LOAD DATA IN BRONZE TABLE
LOAD DATA INFILE '/var/lib/mysql-files/customers.csv'
INTO TABLE bronze_customers
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    customer_id,
    company_name,
    contact_name,
    phone,
    email,
    address,
    city,
    state,
    zip,
    country,
    created_date,
    status
);

#PROFILING
USE gigavolt;
-- ============================================================
-- PROJECT GIGAVOLT
-- FINAL RAW DATA PROFILING - CUSTOMERS
-- Bronze layer only - NO DATA IS MODIFIED
-- ============================================================
-- ============================================================
-- 1. BASIC ROW COUNT AND DUPLICATE PROFILE
-- ============================================================
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS unique_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_rows
FROM bronze_customers;

-- ============================================================
-- 2. MISSING VALUES
-- ============================================================
SELECT
    SUM(customer_id IS NULL OR TRIM(customer_id) = '') AS missing_customer_id,
    SUM(company_name IS NULL OR TRIM(company_name) = '') AS missing_company_name,
    SUM(contact_name IS NULL OR TRIM(contact_name) = '') AS missing_contact_name,
    SUM(phone IS NULL OR TRIM(phone) = '') AS missing_phone,
    SUM(email IS NULL OR TRIM(email) = '') AS missing_email,
    SUM(address IS NULL OR TRIM(address) = '') AS missing_address,
    SUM(city IS NULL OR TRIM(city) = '') AS missing_city,
    SUM(state IS NULL OR TRIM(state) = '') AS missing_state,
    SUM(zip IS NULL OR TRIM(zip) = '') AS missing_zip,
    SUM(country IS NULL OR TRIM(country) = '') AS missing_country,
    SUM(created_date IS NULL OR TRIM(created_date) = '') AS missing_created_date,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status
FROM bronze_customers;
-- ============================================================
-- 3. DUPLICATE CUSTOMER IDs
-- ============================================================
SELECT
    customer_id,
    COUNT(*) AS occurrences
FROM bronze_customers
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, customer_id;

-- ============================================================
-- 4. COUNTRY VALUE PROFILE
-- ============================================================
SELECT
    CASE
        WHEN country IS NULL OR TRIM(country) = ''
            THEN 'NULL / Blank'

        WHEN UPPER(TRIM(country)) IN
            ('US', 'USA', 'UNITED STATES')
            THEN 'Valid US variant'

        WHEN UPPER(TRIM(country)) LIKE '%UNITED STATES%'
          OR UPPER(TRIM(country)) LIKE '%NITED STATES%'
          OR UPPER(TRIM(country)) LIKE '%TED STATES%'
            THEN 'Corrupted United States variant'

        ELSE 'Other / suspicious'
    END AS country_category,

    COUNT(*) AS row_count

FROM bronze_customers
GROUP BY country_category
ORDER BY row_count DESC;
-- ============================================================
-- 5. SHOW ALL DISTINCT RAW COUNTRY VALUES
-- ============================================================
SELECT
    country,
    COUNT(*) AS row_count
FROM bronze_customers
GROUP BY country
ORDER BY row_count DESC;
-- ============================================================
-- 6. SHOW SUSPICIOUS COUNTRY VALUES
-- ============================================================
SELECT
    source_row_id,
    customer_id,
    country
FROM bronze_customers
WHERE country IS NOT NULL
  AND TRIM(country) <> ''
  AND UPPER(TRIM(country)) NOT IN
      ('US', 'USA', 'UNITED STATES')
ORDER BY source_row_id;
-- ============================================================
-- 7. STATUS PROFILE
-- ============================================================
-- CHAR(13) = carriage return
-- CHAR(10) = line feed
SELECT
    REPLACE(
        REPLACE(status, CHAR(13), '[CR]'),
        CHAR(10), '[LF]'
    ) AS visible_status,
    COUNT(*) AS row_count
FROM bronze_customers
GROUP BY visible_status
ORDER BY row_count DESC;
-- ============================================================
-- 8. STATUS AFTER REMOVING HIDDEN CHARACTERS
-- ============================================================
SELECT
    LOWER(
        TRIM(
            REPLACE(
                REPLACE(status, CHAR(13), ''),
                CHAR(10), ''
            )
        )
    ) AS cleaned_status,
    COUNT(*) AS row_count
FROM bronze_customers
GROUP BY cleaned_status
ORDER BY row_count DESC;
-- ============================================================
-- 9. DATE FORMAT PROFILE
-- ============================================================
SELECT
    CASE

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN 'MM-DD-YYYY'

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN 'MM/DD/YYYY'

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN 'YYYY-MM-DD'

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN 'YYYY/MM/DD'

        WHEN TRIM(created_date) LIKE '%T%'
            THEN 'ISO timestamp'

        ELSE 'Other / invalid'

    END AS date_format,

    COUNT(*) AS row_count

FROM bronze_customers
GROUP BY date_format
ORDER BY row_count DESC;
-- ============================================================
-- 10. SHOW VALUES CLASSIFIED AS OTHER / INVALID DATES
-- ============================================================
SELECT
    source_row_id,
    customer_id,
    created_date
FROM bronze_customers
WHERE NOT (
       TRIM(created_date)
       REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'

    OR TRIM(created_date)
       REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'

    OR TRIM(created_date)
       REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

    OR TRIM(created_date)
       REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'

    OR TRIM(created_date) LIKE '%T%'
)
ORDER BY source_row_id;
-- ============================================================
-- 11. HTML TAG PROFILE
-- ============================================================
SELECT
    SUM(company_name REGEXP '<[^>]*>') AS company_name_html,
    SUM(contact_name REGEXP '<[^>]*>') AS contact_name_html,
    SUM(address REGEXP '<[^>]*>') AS address_html
FROM bronze_customers;
-- ============================================================
-- 12. TOTAL ROWS CONTAINING HTML
-- ============================================================
SELECT
    COUNT(*) AS rows_with_html
FROM bronze_customers
WHERE company_name REGEXP '<[^>]*>'
   OR contact_name REGEXP '<[^>]*>'
   OR address REGEXP '<[^>]*>';
-- ============================================================
-- 13. WHITESPACE PROFILE
-- ============================================================
SELECT
    SUM(company_name <> TRIM(company_name)) AS company_name_whitespace,
    SUM(contact_name <> TRIM(contact_name)) AS contact_name_whitespace,
    SUM(phone <> TRIM(phone)) AS phone_whitespace,
    SUM(email <> TRIM(email)) AS email_whitespace,
    SUM(address <> TRIM(address)) AS address_whitespace,
    SUM(city <> TRIM(city)) AS city_whitespace,
    SUM(state <> TRIM(state)) AS state_whitespace,
    SUM(zip <> TRIM(zip)) AS zip_whitespace,
    SUM(country <> TRIM(country)) AS country_whitespace,
    SUM(created_date <> TRIM(created_date)) AS created_date_whitespace,
    SUM(status <> TRIM(status)) AS status_whitespace
FROM bronze_customers;

-- ============================================================
-- 14. PHONE FORMAT PROFILE
-- ============================================================
SELECT
    CASE
        WHEN TRIM(phone) REGEXP '^[0-9]{10}$'
            THEN '10 digits'
        WHEN TRIM(phone) REGEXP '^[0-9]{11}$'
            THEN '11 digits'
        WHEN TRIM(phone) LIKE '+%'
            THEN 'International (+)'
        WHEN TRIM(phone) LIKE '(%'
            THEN 'Parentheses'
        WHEN TRIM(phone) LIKE '%-%'
            THEN 'Hyphenated'
        WHEN TRIM(phone) LIKE '%.%'
            THEN 'Dotted'
        WHEN TRIM(phone) LIKE '% %'
            THEN 'Space separated'
        ELSE 'Other'
    END AS phone_format,
    COUNT(*) AS row_count
FROM bronze_customers
GROUP BY phone_format
ORDER BY row_count DESC;
-- ============================================================
-- 15. EMAIL BASIC PROFILE
-- ============================================================
SELECT
    COUNT(*) AS total_emails,
    SUM(email NOT LIKE '%@%') AS emails_without_at_symbol,
    SUM(email NOT LIKE '%.%') AS emails_without_dot
FROM bronze_customers;
-- ============================================================
-- 16. CHECK FOR HIDDEN CONTROL CHARACTERS
-- ============================================================
SELECT
    SUM(company_name LIKE CONCAT('%', CHAR(13), '%')) AS company_cr,
    SUM(contact_name LIKE CONCAT('%', CHAR(13), '%')) AS contact_cr,
    SUM(phone LIKE CONCAT('%', CHAR(13), '%')) AS phone_cr,
    SUM(email LIKE CONCAT('%', CHAR(13), '%')) AS email_cr,
    SUM(address LIKE CONCAT('%', CHAR(13), '%')) AS address_cr,
    SUM(country LIKE CONCAT('%', CHAR(13), '%')) AS country_cr,
    SUM(created_date LIKE CONCAT('%', CHAR(13), '%')) AS date_cr,
    SUM(status LIKE CONCAT('%', CHAR(13), '%')) AS status_cr
FROM bronze_customers;

-- ============================================================
-- 17. CUSTOMER ID FORMAT
-- ============================================================
SELECT
    CASE
        WHEN TRIM(customer_id) REGEXP '^C-[0-9]+$'
            THEN 'Valid C-ID format'
        ELSE 'Other / invalid'
    END AS customer_id_format,
    COUNT(*) AS row_count
FROM bronze_customers
GROUP BY customer_id_format;
-- ============================================================
-- 18. RAW DATE RANGE
-- ============================================================
SELECT
    MIN(created_date) AS minimum_raw_created_date,
    MAX(created_date) AS maximum_raw_created_date
FROM bronze_customers;
-- ============================================================
-- 19. SAMPLE DIRTY RECORDS
-- ============================================================
SELECT *
FROM bronze_customers
WHERE company_name REGEXP '<[^>]*>'
   OR contact_name <> TRIM(contact_name)
   OR country IS NULL
   OR TRIM(country) = ''
   OR UPPER(TRIM(country)) NOT IN
      ('US', 'USA', 'UNITED STATES')
   OR status LIKE CONCAT('%', CHAR(13), '%')
LIMIT 20;
-- ============================================================
-- 20. FINAL RAW DATA PREVIEW
-- ============================================================
SELECT *
FROM bronze_customers
ORDER BY source_row_id
LIMIT 10;

#SILVER TABLE CREATION

DROP TABLE IF EXISTS silver_customers;
CREATE TABLE silver_customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    contact_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255) NOT NULL,
    address VARCHAR(500) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    zip VARCHAR(20) NOT NULL,
    country VARCHAR(100),
    created_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL
);

#LOAD IN SILVER LAYER

INSERT INTO silver_customers (
    customer_id,
    company_name,
    contact_name,
    phone,
    email,
    address,
    city,
    state,
    zip,
    country,
    created_date,
    status
)
SELECT
    customer_id,

    -- Remove HTML and extra whitespace
    TRIM(
        REGEXP_REPLACE(company_name, '<[^>]*>', '')
    ) AS company_name,

    TRIM(contact_name) AS contact_name,

    -- Standardize phone to 11 digits with leading 1
    CASE
        WHEN LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '')) = 10
            THEN CONCAT('1', REGEXP_REPLACE(phone, '[^0-9]', ''))
        WHEN LENGTH(REGEXP_REPLACE(phone, '[^0-9]', '')) = 11
            THEN REGEXP_REPLACE(phone, '[^0-9]', '')
        ELSE REGEXP_REPLACE(phone, '[^0-9]', '')
    END AS phone,

    TRIM(email) AS email,

    -- Remove HTML and extra whitespace
    TRIM(
        REGEXP_REPLACE(address, '<[^>]*>', '')
    ) AS address,

    TRIM(city) AS city,
    TRIM(state) AS state,
    TRIM(zip) AS zip,

    -- Standardize country
    CASE
        WHEN UPPER(TRIM(country)) IN
            ('US', 'USA', 'UNITED STATES')
            THEN 'USA'
        WHEN country IS NULL OR TRIM(country) = ''
            THEN NULL
        ELSE TRIM(country)
    END AS country,

    -- Convert all supported date formats to DATE
    CASE
        WHEN TRIM(created_date) LIKE '%T%'
            THEN DATE(SUBSTRING_INDEX(TRIM(created_date), 'T', 1))

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN STR_TO_DATE(TRIM(created_date), '%m-%d-%Y')

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN STR_TO_DATE(TRIM(created_date), '%m/%d/%Y')

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(TRIM(created_date), '%Y-%m-%d')

        WHEN TRIM(created_date)
             REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN STR_TO_DATE(TRIM(created_date), '%Y/%m/%d')
    END AS created_date,

    -- Remove hidden CR/LF and standardize case
    LOWER(
        TRIM(
            REPLACE(
                REPLACE(status, CHAR(13), ''),
                CHAR(10), ''
            )
        )
    ) AS status

FROM bronze_customers b
WHERE source_row_id = (
    SELECT MAX(b2.source_row_id)
    FROM bronze_customers b2
    WHERE b2.customer_id = b.customer_id
);

#VALIDATE SILVER CUSTOMERS

USE gigavolt;
-- 1. Row count and unique IDs
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS unique_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_rows
FROM silver_customers;

-- 2. Check missing required fields
SELECT
    SUM(customer_id IS NULL OR TRIM(customer_id) = '') AS missing_customer_id,
    SUM(company_name IS NULL OR TRIM(company_name) = '') AS missing_company_name,
    SUM(contact_name IS NULL OR TRIM(contact_name) = '') AS missing_contact_name,
    SUM(phone IS NULL OR TRIM(phone) = '') AS missing_phone,
    SUM(email IS NULL OR TRIM(email) = '') AS missing_email,
    SUM(address IS NULL OR TRIM(address) = '') AS missing_address,
    SUM(city IS NULL OR TRIM(city) = '') AS missing_city,
    SUM(state IS NULL OR TRIM(state) = '') AS missing_state,
    SUM(zip IS NULL OR TRIM(zip) = '') AS missing_zip,
    SUM(created_date IS NULL) AS missing_created_date,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status
FROM silver_customers;

-- 3. Country standardization
SELECT
    country,
    COUNT(*) AS row_count
FROM silver_customers
GROUP BY country
ORDER BY row_count DESC;

-- 4. Status standardization
SELECT
    status,
    COUNT(*) AS row_count
FROM silver_customers
GROUP BY status
ORDER BY row_count DESC;

-- 5. Date range
SELECT
    MIN(created_date) AS earliest_created_date,
    MAX(created_date) AS latest_created_date
FROM silver_customers;

-- 6. Check HTML removal
SELECT COUNT(*) AS remaining_html_rows
FROM silver_customers
WHERE company_name REGEXP '<[^>]*>'
   OR address REGEXP '<[^>]*>';

-- 7. Check hidden carriage returns
SELECT
    SUM(company_name LIKE CONCAT('%', CHAR(13), '%')) AS company_cr,
    SUM(contact_name LIKE CONCAT('%', CHAR(13), '%')) AS contact_cr,
    SUM(phone LIKE CONCAT('%', CHAR(13), '%')) AS phone_cr,
    SUM(email LIKE CONCAT('%', CHAR(13), '%')) AS email_cr,
    SUM(address LIKE CONCAT('%', CHAR(13), '%')) AS address_cr,
    SUM(status LIKE CONCAT('%', CHAR(13), '%')) AS status_cr
FROM silver_customers;

-- 8. Check phone length
SELECT
    CASE
        WHEN phone REGEXP '^1[0-9]{10}$'
            THEN '11-digit US format'
        ELSE 'Other'
    END AS phone_format,
    COUNT(*) AS row_count
FROM silver_customers
GROUP BY phone_format;

-- 9. Final sample
SELECT *
FROM silver_customers
ORDER BY customer_id
LIMIT 10;

























-- ============================================================
-- EQUIPMENT DATASET
-- ============================================================

#CREATE BRONZE TABLE

USE gigavolt;
DROP TABLE IF EXISTS bronze_equipment;
CREATE TABLE bronze_equipment (
    source_row_id INT AUTO_INCREMENT PRIMARY KEY,
    equipment_id VARCHAR(50),
    customer_id VARCHAR(50),
    model VARCHAR(255),
    serial_number VARCHAR(100),
    install_date VARCHAR(100),
    capacity_kw VARCHAR(50),
    voltage_v VARCHAR(50),
    warranty_expiration VARCHAR(100),
    status VARCHAR(50),
    location_notes VARCHAR(500)
);

#LOAD DATA IN BRONZE TABLE
USE gigavolt;
LOAD DATA INFILE '/var/lib/mysql-files/equipment.csv'
INTO TABLE bronze_equipment
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    equipment_id,
    customer_id,
    model,
    serial_number,
    install_date,
    capacity_kw,
    voltage_v,
    warranty_expiration,
    status,
    location_notes
);

#PROFILING
USE gigavolt;
-- ============================================================
-- EQUIPMENT BRONZE: COMPLETE PROFILING
-- Bronze layer only - NO DATA IS MODIFIED
-- ============================================================
#1. BASIC ROW COUNT AND DUPLICATE PROFILE
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT equipment_id) AS unique_equipment_ids,
    COUNT(*) - COUNT(DISTINCT equipment_id) AS duplicate_rows
FROM bronze_equipment;

#2. DUPLICATE EQUIPMENT IDs
SELECT
    equipment_id,
    COUNT(*) AS occurrences
FROM bronze_equipment
GROUP BY equipment_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, equipment_id;

#3. MISSING VALUES
SELECT
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(customer_id IS NULL OR TRIM(customer_id) = '') AS missing_customer_id,
    SUM(model IS NULL OR TRIM(model) = '') AS missing_model,
    SUM(serial_number IS NULL OR TRIM(serial_number) = '') AS missing_serial_number,
    SUM(install_date IS NULL OR TRIM(install_date) = '') AS missing_install_date,
    SUM(capacity_kw IS NULL OR TRIM(capacity_kw) = '') AS missing_capacity_kw,
    SUM(voltage_v IS NULL OR TRIM(voltage_v) = '') AS missing_voltage_v,
    SUM(warranty_expiration IS NULL OR TRIM(warranty_expiration) = '') AS missing_warranty_expiration,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status,
    SUM(location_notes IS NULL OR TRIM(location_notes) = '') AS missing_location_notes
FROM bronze_equipment;

#4. EQUIPMENT ID FORMAT
SELECT
    CASE
        WHEN equipment_id REGEXP '^EQ-[0-9]+$'
            THEN 'Valid EQ format'
        ELSE 'Invalid EQ format'
    END AS id_format,
    COUNT(*) AS row_count
FROM bronze_equipment
GROUP BY id_format;

#5. CUSTOMER ID FORMAT
SELECT
    CASE
        WHEN customer_id REGEXP '^C-[0-9]+$'
            THEN 'Valid C format'
        ELSE 'Invalid C format'
    END AS id_format,
    COUNT(*) AS row_count
FROM bronze_equipment
GROUP BY id_format;

#6. CUSTOMER FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_customer_rows
FROM bronze_equipment e
LEFT JOIN silver_customers c
    ON e.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

#7. INSTALL DATE FORMAT PROFILE
SELECT
    CASE
        WHEN TRIM(install_date) LIKE '%T%'
            THEN 'ISO timestamp'
        WHEN TRIM(install_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN 'MM/DD/YYYY'
        WHEN TRIM(install_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN 'MM-DD-YYYY'
        WHEN TRIM(install_date) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN 'YYYY-MM-DD'
        WHEN TRIM(install_date) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN 'YYYY/MM/DD'
        ELSE 'Other/Invalid'
    END AS date_format,
    COUNT(*) AS row_count
FROM bronze_equipment
GROUP BY date_format
ORDER BY row_count DESC;

#8. WARRANTY EXPIRATION DATE FORMAT PROFILE
SELECT
    CASE
        WHEN TRIM(warranty_expiration) LIKE '%T%'
            THEN 'ISO timestamp'
        WHEN TRIM(warranty_expiration) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN 'MM/DD/YYYY'
        WHEN TRIM(warranty_expiration) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN 'MM-DD-YYYY'
        WHEN TRIM(warranty_expiration) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN 'YYYY-MM-DD'
        WHEN TRIM(warranty_expiration) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN 'YYYY/MM/DD'
        ELSE 'Other/Invalid'
    END AS date_format,
    COUNT(*) AS row_count
FROM bronze_equipment
GROUP BY date_format
ORDER BY row_count DESC;

#9. CAPACITY VALUES AND NUMERIC FORMAT
SELECT
    COUNT(*) AS total_rows,
    SUM(capacity_kw IS NULL OR TRIM(capacity_kw) = '') AS missing,
    SUM(TRIM(capacity_kw) REGEXP '^[0-9]+(\\.[0-9]+)?$') AS numeric_values,
    SUM(
        NOT (
            TRIM(capacity_kw) REGEXP '^[0-9]+(\\.[0-9]+)?$'
        )
        AND TRIM(capacity_kw) <> ''
    ) AS non_numeric_values
FROM bronze_equipment;

#10. VOLTAGE VALUES AND FORMAT
SELECT
    COUNT(*) AS total_rows,
    SUM(voltage_v IS NULL OR TRIM(voltage_v) = '') AS missing,
    SUM(TRIM(voltage_v) REGEXP '^[0-9]+$') AS numeric_values,
    SUM(
        NOT (
            TRIM(voltage_v) REGEXP '^[0-9]+$'
        )
        AND TRIM(voltage_v) <> ''
    ) AS non_numeric_values
FROM bronze_equipment;

#11. CAPACITY RANGE
SELECT
    MIN(CAST(capacity_kw AS DECIMAL(10,2))) AS min_capacity_kw,
    MAX(CAST(capacity_kw AS DECIMAL(10,2))) AS max_capacity_kw
FROM bronze_equipment
WHERE TRIM(capacity_kw) REGEXP '^[0-9]+(\\.[0-9]+)?$';

#12. VOLTAGE RANGE
SELECT
    MIN(
        CAST(
            REGEXP_REPLACE(TRIM(voltage_v), '[^0-9]', '')
            AS UNSIGNED
        )
    ) AS min_voltage_v,

    MAX(
        CAST(
            REGEXP_REPLACE(TRIM(voltage_v), '[^0-9]', '')
            AS UNSIGNED
        )
    ) AS max_voltage_v
FROM bronze_equipment;


#13. STATUS VALUES
SELECT
    REPLACE(
        REPLACE(
            LOWER(TRIM(status)),
            CHAR(13),
            '[CR]'
        ),
        CHAR(10),
        '[LF]'
    ) AS status_value,
    COUNT(*) AS row_count
FROM bronze_equipment
GROUP BY status_value
ORDER BY row_count DESC;

#14. HTML CONTENT CHECK
SELECT
    SUM(model REGEXP '<[^>]*>') AS model_html,
    SUM(serial_number REGEXP '<[^>]*>') AS serial_html,
    SUM(location_notes REGEXP '<[^>]*>') AS location_notes_html,
    SUM(
        model REGEXP '<[^>]*>'
        OR serial_number REGEXP '<[^>]*>'
        OR location_notes REGEXP '<[^>]*>'
    ) AS rows_with_html
FROM bronze_equipment;

#15. LEADING AND TRAILING WHITESPACE CHECK
SELECT
    SUM(model <> TRIM(model)) AS model_whitespace,
    SUM(serial_number <> TRIM(serial_number)) AS serial_whitespace,
    SUM(location_notes <> TRIM(location_notes)) AS location_notes_whitespace,
    SUM(status <> TRIM(status)) AS status_whitespace,
    SUM(customer_id <> TRIM(customer_id)) AS customer_id_whitespace,
    SUM(equipment_id <> TRIM(equipment_id)) AS equipment_id_whitespace
FROM bronze_equipment;

#16. HIDDEN CARRIAGE RETURNS AND LINE BREAKS
SELECT
    SUM(equipment_id LIKE CONCAT('%', CHAR(13), '%')) AS equipment_id_cr,
    SUM(customer_id LIKE CONCAT('%', CHAR(13), '%')) AS customer_id_cr,
    SUM(model LIKE CONCAT('%', CHAR(13), '%')) AS model_cr,
    SUM(serial_number LIKE CONCAT('%', CHAR(13), '%')) AS serial_number_cr,
    SUM(install_date LIKE CONCAT('%', CHAR(13), '%')) AS install_date_cr,
    SUM(capacity_kw LIKE CONCAT('%', CHAR(13), '%')) AS capacity_cr,
    SUM(voltage_v LIKE CONCAT('%', CHAR(13), '%')) AS voltage_cr,
    SUM(warranty_expiration LIKE CONCAT('%', CHAR(13), '%')) AS warranty_cr,
    SUM(status LIKE CONCAT('%', CHAR(13), '%')) AS status_cr,
    SUM(location_notes LIKE CONCAT('%', CHAR(13), '%')) AS location_notes_cr
FROM bronze_equipment;

#17. SERIAL NUMBER PROFILE
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT NULLIF(TRIM(serial_number), '')) AS unique_serial_numbers,
    SUM(serial_number IS NULL OR TRIM(serial_number) = '') AS missing_serial_numbers
FROM bronze_equipment;

#18. CHECK FOR INVALID DATE VALUES
SELECT
    install_date,
    warranty_expiration
FROM bronze_equipment
WHERE
    (
        TRIM(install_date) <> ''
        AND (
            (
                TRIM(install_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                AND STR_TO_DATE(TRIM(install_date), '%m/%d/%Y') IS NULL
            )
            OR
            (
                TRIM(install_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
                AND STR_TO_DATE(TRIM(install_date), '%m-%d-%Y') IS NULL
            )
        )
    )
    OR
    (
        TRIM(warranty_expiration) <> ''
        AND (
            (
                TRIM(warranty_expiration) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                AND STR_TO_DATE(
                    TRIM(warranty_expiration),
                    '%m/%d/%Y'
                ) IS NULL
            )
            OR
            (
                TRIM(warranty_expiration) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
                AND STR_TO_DATE(
                    TRIM(warranty_expiration),
                    '%m-%d-%Y'
                ) IS NULL
            )
        )
    );

#19. INSTALL DATE RANGE AFTER NORMALIZATION
SELECT
    MIN(
        CASE
            WHEN TRIM(install_date) LIKE '%T%'
                THEN DATE(SUBSTRING_INDEX(TRIM(install_date), 'T', 1))

            WHEN TRIM(install_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
                THEN STR_TO_DATE(TRIM(install_date), '%m-%d-%Y')

            WHEN TRIM(install_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                THEN STR_TO_DATE(TRIM(install_date), '%m/%d/%Y')

            WHEN TRIM(install_date) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN STR_TO_DATE(TRIM(install_date), '%Y-%m-%d')

            WHEN TRIM(install_date) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
                THEN STR_TO_DATE(TRIM(install_date), '%Y/%m/%d')
        END
    ) AS earliest_install_date,

    MAX(
        CASE
            WHEN TRIM(install_date) LIKE '%T%'
                THEN DATE(SUBSTRING_INDEX(TRIM(install_date), 'T', 1))

            WHEN TRIM(install_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
                THEN STR_TO_DATE(TRIM(install_date), '%m-%d-%Y')

            WHEN TRIM(install_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                THEN STR_TO_DATE(TRIM(install_date), '%m/%d/%Y')

            WHEN TRIM(install_date) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN STR_TO_DATE(TRIM(install_date), '%Y-%m-%d')

            WHEN TRIM(install_date) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
                THEN STR_TO_DATE(TRIM(install_date), '%Y/%m/%d')
        END
    ) AS latest_install_date
FROM bronze_equipment;

#20. SAMPLE RAW EQUIPMENT RECORDS
SELECT *
FROM bronze_equipment
LIMIT 10;

#SILVER TABLE CREATION
DROP TABLE IF EXISTS silver_equipment;
CREATE TABLE silver_equipment (
    equipment_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    model VARCHAR(255) NOT NULL,
    serial_number VARCHAR(100),
    install_date DATE NOT NULL,
    capacity_kw DECIMAL(10,2) NOT NULL,
    voltage_v INT NOT NULL,
    warranty_expiration DATE NOT NULL,
    status VARCHAR(30) NOT NULL,
    location_notes VARCHAR(500),

    CONSTRAINT fk_equipment_customer
        FOREIGN KEY (customer_id)
        REFERENCES silver_customers(customer_id)
);

#LOAD CLEANED DATA INTO SILVER
INSERT INTO silver_equipment (
    equipment_id,
    customer_id,
    model,
    serial_number,
    install_date,
    capacity_kw,
    voltage_v,
    warranty_expiration,
    status,
    location_notes
)
SELECT
    equipment_id,

    TRIM(customer_id) AS customer_id,

    TRIM(model) AS model,

    CASE
        WHEN serial_number IS NULL OR TRIM(serial_number) = ''
            THEN NULL
        ELSE TRIM(serial_number)
    END AS serial_number,

    #CONVERT INSTALL DATE TO DATE FORMAT
    CASE
        WHEN TRIM(install_date) LIKE '%T%'
            THEN DATE(SUBSTRING_INDEX(TRIM(install_date), 'T', 1))

        WHEN TRIM(install_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN STR_TO_DATE(TRIM(install_date), '%m-%d-%Y')

        WHEN TRIM(install_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN STR_TO_DATE(TRIM(install_date), '%m/%d/%Y')

        WHEN TRIM(install_date) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(TRIM(install_date), '%Y-%m-%d')

        WHEN TRIM(install_date) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN STR_TO_DATE(TRIM(install_date), '%Y/%m/%d')
    END AS install_date,

    #CONVERT CAPACITY TO DECIMAL
    CAST(TRIM(capacity_kw) AS DECIMAL(10,2)) AS capacity_kw,
    #REMOVE V FROM VOLTAGE AND CONVERT TO INTEGER
    CAST(
        REGEXP_REPLACE(TRIM(voltage_v), '[^0-9]', '')
        AS UNSIGNED
    ) AS voltage_v,

    #CONVERT WARRANTY EXPIRATION TO DATE
    CASE
        WHEN TRIM(warranty_expiration) LIKE '%T%'
            THEN DATE(
                SUBSTRING_INDEX(
                    TRIM(warranty_expiration),
                    'T',
                    1
                )
            )

        WHEN TRIM(warranty_expiration)
             REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(warranty_expiration),
                '%m-%d-%Y'
            )

        WHEN TRIM(warranty_expiration)
             REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(warranty_expiration),
                '%m/%d/%Y'
            )

        WHEN TRIM(warranty_expiration)
             REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(warranty_expiration),
                '%Y-%m-%d'
            )

        WHEN TRIM(warranty_expiration)
             REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(warranty_expiration),
                '%Y/%m/%d'
            )
    END AS warranty_expiration,

    #STANDARDIZE STATUS
    LOWER(
        TRIM(
            REPLACE(
                REPLACE(status, CHAR(13), ''),
                CHAR(10), ''
            )
        )
    ) AS status,


    #REMOVE HTML, CR/LF AND WHITESPACE FROM LOCATION NOTES

    NULLIF(
        TRIM(
            REGEXP_REPLACE(
                REPLACE(
                    REPLACE(location_notes, CHAR(13), ''),
                    CHAR(10), ''
                ),
                '<[^>]*>',
                ''
            )
        ),
        ''
    ) AS location_notes


FROM bronze_equipment b

#REMOVE DUPLICATE EQUIPMENT IDS

WHERE source_row_id = (
    SELECT MAX(b2.source_row_id)
    FROM bronze_equipment b2
    WHERE b2.equipment_id = b.equipment_id
);


#VALIDATE SILVER EQUIPMENT

USE gigavolt;

#1. ROW COUNT AND DUPLICATES
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT equipment_id) AS unique_equipment_ids,
    COUNT(*) - COUNT(DISTINCT equipment_id) AS duplicate_rows
FROM silver_equipment;

#2. MISSING VALUES
SELECT
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(customer_id IS NULL OR TRIM(customer_id) = '') AS missing_customer_id,
    SUM(model IS NULL OR TRIM(model) = '') AS missing_model,
    SUM(serial_number IS NULL OR TRIM(serial_number) = '') AS missing_serial_number,
    SUM(install_date IS NULL) AS missing_install_date,
    SUM(capacity_kw IS NULL) AS missing_capacity_kw,
    SUM(voltage_v IS NULL) AS missing_voltage_v,
    SUM(warranty_expiration IS NULL) AS missing_warranty_expiration,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status
FROM silver_equipment;

#3. CUSTOMER FOREIGN KEY VALIDATION
SELECT
    COUNT(*) AS orphan_customer_rows
FROM silver_equipment e
LEFT JOIN silver_customers c
    ON e.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
#4. EQUIPMENT ID FORMAT
SELECT
    CASE
        WHEN equipment_id REGEXP '^EQ-[0-9]+$'
            THEN 'Valid EQ format'
        ELSE 'Invalid EQ format'
    END AS id_format,
    COUNT(*) AS row_count
FROM silver_equipment
GROUP BY id_format;

#5. CUSTOMER ID FORMAT
SELECT
    CASE
        WHEN customer_id REGEXP '^C-[0-9]+$'
            THEN 'Valid C format'
        ELSE 'Invalid C format'
    END AS id_format,
    COUNT(*) AS row_count
FROM silver_equipment
GROUP BY id_format;

#6. STATUS DISTRIBUTION
SELECT
    status,
    COUNT(*) AS row_count
FROM silver_equipment
GROUP BY status
ORDER BY row_count DESC;

#7. CAPACITY RANGE
SELECT
    MIN(capacity_kw) AS min_capacity_kw,
    MAX(capacity_kw) AS max_capacity_kw,
    AVG(capacity_kw) AS avg_capacity_kw
FROM silver_equipment;

#8. VOLTAGE DISTRIBUTION
SELECT
    voltage_v,
    COUNT(*) AS row_count
FROM silver_equipment
GROUP BY voltage_v
ORDER BY voltage_v;

#9. INSTALL DATE RANGE
SELECT
    MIN(install_date) AS earliest_install_date,
    MAX(install_date) AS latest_install_date
FROM silver_equipment;

#10. WARRANTY EXPIRATION RANGE
SELECT
    MIN(warranty_expiration) AS earliest_warranty_expiration,
    MAX(warranty_expiration) AS latest_warranty_expiration
FROM silver_equipment;

#11. HTML CHECK
SELECT
    SUM(
        model REGEXP '<[^>]*>'
        OR serial_number REGEXP '<[^>]*>'
        OR location_notes REGEXP '<[^>]*>'
    ) AS rows_with_html
FROM silver_equipment;

#12. HIDDEN CR/LF CHECK
SELECT
    SUM(
        equipment_id LIKE CONCAT('%', CHAR(13), '%')
        OR equipment_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS equipment_id_control_chars,

    SUM(
        customer_id LIKE CONCAT('%', CHAR(13), '%')
        OR customer_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS customer_id_control_chars,

    SUM(
        model LIKE CONCAT('%', CHAR(13), '%')
        OR model LIKE CONCAT('%', CHAR(10), '%')
    ) AS model_control_chars,

    SUM(
        serial_number LIKE CONCAT('%', CHAR(13), '%')
        OR serial_number LIKE CONCAT('%', CHAR(10), '%')
    ) AS serial_control_chars,

    SUM(
        status LIKE CONCAT('%', CHAR(13), '%')
        OR status LIKE CONCAT('%', CHAR(10), '%')
    ) AS status_control_chars,

    SUM(
        location_notes LIKE CONCAT('%', CHAR(13), '%')
        OR location_notes LIKE CONCAT('%', CHAR(10), '%')
    ) AS location_control_chars

FROM silver_equipment;
#13. SERIAL NUMBER PROFILE

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT serial_number) AS unique_serial_numbers,
    SUM(serial_number IS NULL) AS null_serial_numbers
FROM silver_equipment;

#14. CHECK INSTALL DATE IS BEFORE WARRANTY EXPIRATION
SELECT
    COUNT(*) AS invalid_date_relationships
FROM silver_equipment
WHERE install_date > warranty_expiration;

#15. SAMPLE CLEANED EQUIPMENT RECORDS
SELECT *
FROM silver_equipment
LIMIT 10;















-- ============================================================
-- PARTS DATASET
-- ============================================================

#CREATE BRONZE TABLE
USE gigavolt;
DROP TABLE IF EXISTS bronze_parts;
CREATE TABLE bronze_parts (
    source_row_id INT AUTO_INCREMENT PRIMARY KEY,
    part_id VARCHAR(50),
    part_name VARCHAR(255),
    category VARCHAR(100),
    manufacturer VARCHAR(255),
    supplier VARCHAR(255),
    unit_cost VARCHAR(50),
    unit_price VARCHAR(50),
    stock_quantity VARCHAR(50),
    reorder_level VARCHAR(50)
);

#LOAD DATA IN BRONZE TABLE
LOAD DATA INFILE '/var/lib/mysql-files/parts.csv'
INTO TABLE bronze_parts
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    part_id,
    part_name,
    category,
    manufacturer,
    supplier,
    unit_cost,
    unit_price,
    stock_quantity,
    reorder_level
);

#PROFILING

#1. BASIC ROW COUNT AND DUPLICATE CHECK
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT part_id) AS unique_part_ids,
    COUNT(*) - COUNT(DISTINCT part_id) AS duplicate_rows
FROM bronze_parts;

#2. MISSING VALUES
SELECT
    SUM(part_id IS NULL OR TRIM(part_id) = '') AS missing_part_id,
    SUM(part_name IS NULL OR TRIM(part_name) = '') AS missing_part_name,
    SUM(category IS NULL OR TRIM(category) = '') AS missing_category,
    SUM(manufacturer IS NULL OR TRIM(manufacturer) = '') AS missing_manufacturer,
    SUM(supplier IS NULL OR TRIM(supplier) = '') AS missing_supplier,
    SUM(unit_cost IS NULL OR TRIM(unit_cost) = '') AS missing_unit_cost,
    SUM(unit_price IS NULL OR TRIM(unit_price) = '') AS missing_unit_price,
    SUM(stock_quantity IS NULL OR TRIM(stock_quantity) = '') AS missing_stock_quantity,
    SUM(reorder_level IS NULL OR TRIM(reorder_level) = '') AS missing_reorder_level
FROM bronze_parts;

#3. PART ID FORMAT
-- IMPORTANT:
-- Actual Part IDs use the PRT-#### format.

SELECT
    CASE
        WHEN TRIM(part_id) REGEXP '^PRT-[0-9]+$'
            THEN 'Valid PRT format'
        ELSE 'Invalid PRT format'
    END AS id_format,
    COUNT(*) AS row_count
FROM bronze_parts
GROUP BY id_format;

#4. UNIT COST PROFILE
SELECT
    MIN(CAST(TRIM(unit_cost) AS DECIMAL(10,2))) AS min_unit_cost,
    MAX(CAST(TRIM(unit_cost) AS DECIMAL(10,2))) AS max_unit_cost,
    AVG(CAST(TRIM(unit_cost) AS DECIMAL(10,2))) AS avg_unit_cost
FROM bronze_parts;

#5. UNIT PRICE PROFILE
SELECT
    MIN(CAST(TRIM(unit_price) AS DECIMAL(10,2))) AS min_unit_price,
    MAX(CAST(TRIM(unit_price) AS DECIMAL(10,2))) AS max_unit_price,
    AVG(CAST(TRIM(unit_price) AS DECIMAL(10,2))) AS avg_unit_price
FROM bronze_parts;

#6. STOCK QUANTITY PROFILE
SELECT
    MIN(CAST(TRIM(stock_quantity) AS UNSIGNED)) AS min_stock_quantity,
    MAX(CAST(TRIM(stock_quantity) AS UNSIGNED)) AS max_stock_quantity,
    AVG(CAST(TRIM(stock_quantity) AS UNSIGNED)) AS avg_stock_quantity
FROM bronze_parts;

#7. REORDER LEVEL PROFILE
SELECT
    TRIM(
        REPLACE(
            REPLACE(reorder_level, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS cleaned_reorder_level,
    COUNT(*) AS row_count
FROM bronze_parts
GROUP BY cleaned_reorder_level
ORDER BY CAST(cleaned_reorder_level AS UNSIGNED);

#8. HIDDEN CR/LF CHECK
SELECT
    SUM(
        part_id LIKE CONCAT('%', CHAR(13), '%')
        OR part_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS part_id_control_chars,

    SUM(
        part_name LIKE CONCAT('%', CHAR(13), '%')
        OR part_name LIKE CONCAT('%', CHAR(10), '%')
    ) AS part_name_control_chars,

    SUM(
        category LIKE CONCAT('%', CHAR(13), '%')
        OR category LIKE CONCAT('%', CHAR(10), '%')
    ) AS category_control_chars,

    SUM(
        manufacturer LIKE CONCAT('%', CHAR(13), '%')
        OR manufacturer LIKE CONCAT('%', CHAR(10), '%')
    ) AS manufacturer_control_chars,

    SUM(
        supplier LIKE CONCAT('%', CHAR(13), '%')
        OR supplier LIKE CONCAT('%', CHAR(10), '%')
    ) AS supplier_control_chars,

    SUM(
        unit_cost LIKE CONCAT('%', CHAR(13), '%')
        OR unit_cost LIKE CONCAT('%', CHAR(10), '%')
    ) AS unit_cost_control_chars,

    SUM(
        unit_price LIKE CONCAT('%', CHAR(13), '%')
        OR unit_price LIKE CONCAT('%', CHAR(10), '%')
    ) AS unit_price_control_chars,

    SUM(
        stock_quantity LIKE CONCAT('%', CHAR(13), '%')
        OR stock_quantity LIKE CONCAT('%', CHAR(10), '%')
    ) AS stock_quantity_control_chars,

    SUM(
        reorder_level LIKE CONCAT('%', CHAR(13), '%')
        OR reorder_level LIKE CONCAT('%', CHAR(10), '%')
    ) AS reorder_level_control_chars

FROM bronze_parts;

#9. LEADING AND TRAILING WHITESPACE
SELECT
    SUM(part_id <> TRIM(part_id)) AS part_id_whitespace,
    SUM(part_name <> TRIM(part_name)) AS part_name_whitespace,
    SUM(category <> TRIM(category)) AS category_whitespace,
    SUM(manufacturer <> TRIM(manufacturer)) AS manufacturer_whitespace,
    SUM(supplier <> TRIM(supplier)) AS supplier_whitespace,
    SUM(unit_cost <> TRIM(unit_cost)) AS unit_cost_whitespace,
    SUM(unit_price <> TRIM(unit_price)) AS unit_price_whitespace,
    SUM(stock_quantity <> TRIM(stock_quantity)) AS stock_quantity_whitespace,
    SUM(reorder_level <> TRIM(reorder_level)) AS reorder_level_whitespace
FROM bronze_parts;

#10. HTML CHECK
SELECT
    SUM(
        part_name REGEXP '<[^>]*>'
        OR category REGEXP '<[^>]*>'
        OR manufacturer REGEXP '<[^>]*>'
        OR supplier REGEXP '<[^>]*>'
    ) AS rows_with_html
FROM bronze_parts;

#11. CATEGORY DISTRIBUTION
SELECT
    category,
    COUNT(*) AS row_count
FROM bronze_parts
GROUP BY category
ORDER BY row_count DESC;

#12. PRICE CONSISTENCY CHECK
SELECT
    SUM(
        CAST(TRIM(unit_price) AS DECIMAL(10,2))
        <
        CAST(TRIM(unit_cost) AS DECIMAL(10,2))
    ) AS price_below_cost
FROM bronze_parts;

#13. NEGATIVE VALUE CHECK
SELECT
    SUM(CAST(TRIM(unit_cost) AS DECIMAL(10,2)) < 0) AS negative_unit_cost,
    SUM(CAST(TRIM(unit_price) AS DECIMAL(10,2)) < 0) AS negative_unit_price,
    SUM(CAST(TRIM(stock_quantity) AS SIGNED) < 0) AS negative_stock_quantity,

    SUM(
        CAST(
            TRIM(
                REPLACE(
                    REPLACE(reorder_level, CHAR(13), ''),
                    CHAR(10), ''
                )
            ) AS SIGNED
        ) < 0
    ) AS negative_reorder_level

FROM bronze_parts;

#14. SAMPLE RAW PARTS RECORDS
SELECT *
FROM bronze_parts
LIMIT 10;

#SILVER TABLE CREATION
USE gigavolt;
DROP TABLE IF EXISTS silver_parts;
CREATE TABLE silver_parts (
    part_id VARCHAR(50) PRIMARY KEY,
    part_name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    manufacturer VARCHAR(255) NOT NULL,
    supplier VARCHAR(255) NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    stock_quantity INT NOT NULL,
    reorder_level INT NOT NULL
);

#LOAD CLEANED DATA INTO SILVER
INSERT INTO silver_parts (
    part_id,
    part_name,
    category,
    manufacturer,
    supplier,
    unit_cost,
    unit_price,
    stock_quantity,
    reorder_level
)
SELECT
    TRIM(part_id) AS part_id,

    #REMOVE WHITESPACE AND CONTROL CHARACTERS
    TRIM(
        REPLACE(
            REPLACE(part_name, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS part_name,

    TRIM(
        REPLACE(
            REPLACE(category, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS category,

    TRIM(
        REPLACE(
            REPLACE(manufacturer, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS manufacturer,

    TRIM(
        REPLACE(
            REPLACE(supplier, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS supplier,


    #CONVERT COST AND PRICE TO DECIMAL
    CAST(TRIM(unit_cost) AS DECIMAL(10,2)) AS unit_cost,
    CAST(TRIM(unit_price) AS DECIMAL(10,2)) AS unit_price,

    #CONVERT INVENTORY VALUES TO INTEGER
    CAST(TRIM(stock_quantity) AS UNSIGNED) AS stock_quantity,
    CAST(
        TRIM(
            REPLACE(
                REPLACE(reorder_level, CHAR(13), ''),
                CHAR(10), ''
            )
        ) AS UNSIGNED
    ) AS reorder_level

FROM bronze_parts;

#VALIDATE SILVER PARTS

#1. ROW COUNT AND DUPLICATES
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT part_id) AS unique_part_ids,
    COUNT(*) - COUNT(DISTINCT part_id) AS duplicate_rows
FROM silver_parts;

#2. MISSING VALUES
SELECT
    SUM(part_id IS NULL OR TRIM(part_id) = '') AS missing_part_id,
    SUM(part_name IS NULL OR TRIM(part_name) = '') AS missing_part_name,
    SUM(category IS NULL OR TRIM(category) = '') AS missing_category,
    SUM(manufacturer IS NULL OR TRIM(manufacturer) = '') AS missing_manufacturer,
    SUM(supplier IS NULL OR TRIM(supplier) = '') AS missing_supplier,
    SUM(unit_cost IS NULL) AS missing_unit_cost,
    SUM(unit_price IS NULL) AS missing_unit_price,
    SUM(stock_quantity IS NULL) AS missing_stock_quantity,
    SUM(reorder_level IS NULL) AS missing_reorder_level
FROM silver_parts;

#3. PART ID FORMAT
SELECT
    CASE
        WHEN part_id REGEXP '^PRT-[0-9]+$'
            THEN 'Valid PRT format'
        ELSE 'Invalid PRT format'
    END AS id_format,
    COUNT(*) AS row_count
FROM silver_parts
GROUP BY id_format;

#4. COST AND PRICE STATISTICS
SELECT
    MIN(unit_cost) AS min_unit_cost,
    MAX(unit_cost) AS max_unit_cost,
    AVG(unit_cost) AS avg_unit_cost,

    MIN(unit_price) AS min_unit_price,
    MAX(unit_price) AS max_unit_price,
    AVG(unit_price) AS avg_unit_price

FROM silver_parts;

#5. INVENTORY STATISTICS
SELECT
    MIN(stock_quantity) AS min_stock_quantity,
    MAX(stock_quantity) AS max_stock_quantity,
    AVG(stock_quantity) AS avg_stock_quantity,

    MIN(reorder_level) AS min_reorder_level,
    MAX(reorder_level) AS max_reorder_level,
    AVG(reorder_level) AS avg_reorder_level

FROM silver_parts;

#6. HIDDEN CONTROL CHARACTER CHECK
SELECT
    SUM(
        part_id LIKE CONCAT('%', CHAR(13), '%')
        OR part_id LIKE CONCAT('%', CHAR(10), '%')
        OR part_name LIKE CONCAT('%', CHAR(13), '%')
        OR part_name LIKE CONCAT('%', CHAR(10), '%')
        OR category LIKE CONCAT('%', CHAR(13), '%')
        OR category LIKE CONCAT('%', CHAR(10), '%')
        OR manufacturer LIKE CONCAT('%', CHAR(13), '%')
        OR manufacturer LIKE CONCAT('%', CHAR(10), '%')
        OR supplier LIKE CONCAT('%', CHAR(13), '%')
        OR supplier LIKE CONCAT('%', CHAR(10), '%')
    ) AS rows_with_control_chars
FROM silver_parts;

#7. HTML CHECK
SELECT
    SUM(
        part_name REGEXP '<[^>]*>'
        OR category REGEXP '<[^>]*>'
        OR manufacturer REGEXP '<[^>]*>'
        OR supplier REGEXP '<[^>]*>'
    ) AS rows_with_html
FROM silver_parts;

#8. INVALID NUMERIC VALUE CHECK
SELECT
    SUM(unit_price < unit_cost) AS price_below_cost,
    SUM(unit_cost < 0) AS negative_unit_cost,
    SUM(unit_price < 0) AS negative_unit_price,
    SUM(stock_quantity < 0) AS negative_stock_quantity,
    SUM(reorder_level < 0) AS negative_reorder_level
FROM silver_parts;

#9. CATEGORY DISTRIBUTION
SELECT
    category,
    COUNT(*) AS row_count
FROM silver_parts
GROUP BY category
ORDER BY row_count DESC;

#10. SAMPLE CLEANED PARTS RECORDS
SELECT *
FROM silver_parts
LIMIT 10;


























-- ============================================================
-- DISPATCHES DATASET
-- DISPATCHES BECOME SERVICE LOGS IN SILVER
-- ============================================================

#CREATE BRONZE TABLE
USE gigavolt;
DROP TABLE IF EXISTS bronze_dispatches;
CREATE TABLE bronze_dispatches (
    source_row_id INT AUTO_INCREMENT PRIMARY KEY,
    dispatch_id VARCHAR(100),
    equipment_id VARCHAR(100),
    customer_id VARCHAR(100),
    dispatch_date VARCHAR(255),
    technician VARCHAR(255),
    service_type VARCHAR(255),
    hours_spent VARCHAR(100),
    labor_cost VARCHAR(100),
    resolution_summary TEXT,
    status VARCHAR(255)
);

#LOAD DATA IN BRONZE TABLE
LOAD DATA INFILE '/var/lib/mysql-files/dispatches.csv'
INTO TABLE bronze_dispatches
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    dispatch_id,
    equipment_id,
    customer_id,
    dispatch_date,
    technician,
    service_type,
    hours_spent,
    labor_cost,
    resolution_summary,
    status
);

#PROFILING

#1. BASIC ROW COUNT AND DUPLICATE PROFILE
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT dispatch_id) AS unique_dispatch_ids,
    COUNT(*) - COUNT(DISTINCT dispatch_id) AS duplicate_rows
FROM bronze_dispatches;

#2. MISSING VALUES
SELECT
    SUM(dispatch_id IS NULL OR TRIM(dispatch_id) = '') AS missing_dispatch_id,
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(customer_id IS NULL OR TRIM(customer_id) = '') AS missing_customer_id,
    SUM(dispatch_date IS NULL OR TRIM(dispatch_date) = '') AS missing_dispatch_date,
    SUM(technician IS NULL OR TRIM(technician) = '') AS missing_technician,
    SUM(service_type IS NULL OR TRIM(service_type) = '') AS missing_service_type,
    SUM(hours_spent IS NULL OR TRIM(hours_spent) = '') AS missing_hours_spent,
    SUM(labor_cost IS NULL OR TRIM(labor_cost) = '') AS missing_labor_cost,
    SUM(resolution_summary IS NULL OR TRIM(resolution_summary) = '') AS missing_resolution_summary,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status
FROM bronze_dispatches;

#3. DISPATCH ID FORMAT
-- Actual Dispatch IDs use the DISP-#### format.

SELECT
    CASE
        WHEN TRIM(dispatch_id) REGEXP '^DISP-[0-9]+$'
            THEN 'Valid DISP-ID format'
        ELSE 'Invalid DISP-ID format'
    END AS dispatch_id_format,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY dispatch_id_format;

#4. EQUIPMENT ID FORMAT
SELECT
    CASE
        WHEN TRIM(equipment_id) REGEXP '^EQ-[0-9]+$'
            THEN 'Valid EQ-ID format'
        ELSE 'Invalid EQ-ID format'
    END AS equipment_id_format,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY equipment_id_format;

#5. CUSTOMER ID FORMAT
SELECT
    CASE
        WHEN TRIM(customer_id) REGEXP '^C-[0-9]+$'
            THEN 'Valid C-ID format'
        ELSE 'Invalid C-ID format'
    END AS customer_id_format,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY customer_id_format;
#6. DISPATCH DATE FORMAT PROFILE
SELECT
    CASE
        WHEN TRIM(dispatch_date) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN 'MM-DD-YYYY'

        WHEN TRIM(dispatch_date) REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN 'MM/DD/YYYY'

        WHEN TRIM(dispatch_date) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN 'YYYY-MM-DD'

        WHEN TRIM(dispatch_date) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN 'YYYY/MM/DD'

        WHEN TRIM(dispatch_date) LIKE '%T%'
            THEN 'ISO timestamp'

        ELSE 'Other / invalid'
    END AS date_format,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY date_format
ORDER BY row_count DESC;

#7. HOURS SPENT PROFILE
SELECT
    MIN(CAST(TRIM(hours_spent) AS DECIMAL(10,2))) AS min_hours,
    MAX(CAST(TRIM(hours_spent) AS DECIMAL(10,2))) AS max_hours,
    AVG(CAST(TRIM(hours_spent) AS DECIMAL(10,2))) AS avg_hours
FROM bronze_dispatches
WHERE TRIM(hours_spent) <> '';


#8. LABOR COST PROFILE
SELECT
    MIN(
        CAST(
            REGEXP_REPLACE(
                TRIM(labor_cost),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(12,2)
        )
    ) AS min_labor_cost,

    MAX(
        CAST(
            REGEXP_REPLACE(
                TRIM(labor_cost),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(12,2)
        )
    ) AS max_labor_cost,

    AVG(
        CAST(
            REGEXP_REPLACE(
                TRIM(labor_cost),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(12,2)
        )
    ) AS avg_labor_cost

FROM bronze_dispatches
WHERE TRIM(labor_cost) <> '';

#9. LABOR COST FORMAT PROFILE
SELECT
    CASE
        WHEN TRIM(labor_cost) LIKE '$%'
            THEN 'Dollar sign ($)'

        WHEN UPPER(TRIM(labor_cost)) LIKE 'USD%'
            THEN 'USD prefix'

        ELSE 'Other'
    END AS labor_cost_format,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY labor_cost_format
ORDER BY row_count DESC;

#10. STATUS VALUES
SELECT
    TRIM(
        REPLACE(
            REPLACE(status, CHAR(13), ''),
            CHAR(10), ''
        )
    ) AS status_clean,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY status_clean
ORDER BY row_count DESC;

#11. SERVICE TYPE VALUES
SELECT
    TRIM(service_type) AS service_type,
    COUNT(*) AS row_count
FROM bronze_dispatches
GROUP BY service_type
ORDER BY row_count DESC;

#12. WHITESPACE CHECK
SELECT
    SUM(technician <> TRIM(technician)) AS technician_whitespace,
    SUM(service_type <> TRIM(service_type)) AS service_type_whitespace,
    SUM(dispatch_id <> TRIM(dispatch_id)) AS dispatch_id_whitespace,
    SUM(equipment_id <> TRIM(equipment_id)) AS equipment_id_whitespace,
    SUM(customer_id <> TRIM(customer_id)) AS customer_id_whitespace
FROM bronze_dispatches;

#13. HIDDEN CONTROL CHARACTER CHECK
SELECT
    SUM(
        dispatch_id LIKE CONCAT('%', CHAR(13), '%')
        OR dispatch_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS dispatch_id_control,

    SUM(
        equipment_id LIKE CONCAT('%', CHAR(13), '%')
        OR equipment_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS equipment_id_control,

    SUM(
        customer_id LIKE CONCAT('%', CHAR(13), '%')
        OR customer_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS customer_id_control,

    SUM(
        dispatch_date LIKE CONCAT('%', CHAR(13), '%')
        OR dispatch_date LIKE CONCAT('%', CHAR(10), '%')
    ) AS date_control,

    SUM(
        technician LIKE CONCAT('%', CHAR(13), '%')
        OR technician LIKE CONCAT('%', CHAR(10), '%')
    ) AS technician_control,

    SUM(
        service_type LIKE CONCAT('%', CHAR(13), '%')
        OR service_type LIKE CONCAT('%', CHAR(10), '%')
    ) AS service_type_control,

    SUM(
        hours_spent LIKE CONCAT('%', CHAR(13), '%')
        OR hours_spent LIKE CONCAT('%', CHAR(10), '%')
    ) AS hours_control,

    SUM(
        labor_cost LIKE CONCAT('%', CHAR(13), '%')
        OR labor_cost LIKE CONCAT('%', CHAR(10), '%')
    ) AS labor_control,

    SUM(
        resolution_summary LIKE CONCAT('%', CHAR(13), '%')
        OR resolution_summary LIKE CONCAT('%', CHAR(10), '%')
    ) AS resolution_control,

    SUM(
        status LIKE CONCAT('%', CHAR(13), '%')
        OR status LIKE CONCAT('%', CHAR(10), '%')
    ) AS status_control

FROM bronze_dispatches;

#14. HTML CHECK
SELECT
    SUM(technician REGEXP '<[^>]*>') AS technician_html,
    SUM(service_type REGEXP '<[^>]*>') AS service_type_html,
    SUM(resolution_summary REGEXP '<[^>]*>') AS resolution_html
FROM bronze_dispatches;


#15. NEGATIVE VALUE CHECK
SELECT
    SUM(
        CAST(TRIM(hours_spent) AS DECIMAL(10,2)) < 0
    ) AS negative_hours,

    SUM(
        CAST(
            REGEXP_REPLACE(
                TRIM(labor_cost),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(12,2)
        ) < 0
    ) AS negative_labor_cost

FROM bronze_dispatches;

#16. CUSTOMER FOREIGN KEY CHECK
SELECT COUNT(*) AS orphan_customer_rows
FROM bronze_dispatches d
LEFT JOIN silver_customers c
    ON TRIM(d.customer_id) = c.customer_id
WHERE c.customer_id IS NULL;

#17. EQUIPMENT FOREIGN KEY CHECK
SELECT COUNT(*) AS orphan_equipment_rows
FROM bronze_dispatches d
LEFT JOIN silver_equipment e
    ON TRIM(d.equipment_id) = e.equipment_id
WHERE e.equipment_id IS NULL;

#18. SAMPLE DIRTY DISPATCH RECORDS
SELECT *
FROM bronze_dispatches
WHERE technician <> TRIM(technician)
   OR resolution_summary REGEXP '<[^>]*>'
   OR labor_cost LIKE '$%'
   OR UPPER(TRIM(labor_cost)) LIKE 'USD%'
   OR status LIKE CONCAT('%', CHAR(13), '%')
LIMIT 20;

#QUARANTINE INVALID DISPATCH RECORDS
USE gigavolt;
DROP TABLE IF EXISTS dq_dispatches;
CREATE TABLE dq_dispatches (
    source_row_id INT PRIMARY KEY,
    dispatch_id VARCHAR(100),
    equipment_id VARCHAR(100),
    customer_id VARCHAR(100),
    reason VARCHAR(500),
    quarantined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

#INSERT INVALID RECORDS INTO QUARANTINE
INSERT INTO dq_dispatches (
    source_row_id,
    dispatch_id,
    equipment_id,
    customer_id,
    reason
)
SELECT
    d.source_row_id,
    d.dispatch_id,
    d.equipment_id,
    d.customer_id,

    CASE

        WHEN c.customer_id IS NULL
             AND e.equipment_id IS NULL
            THEN 'Customer and equipment not found in Silver master tables'

        WHEN c.customer_id IS NULL
            THEN 'Customer not found in silver_customers'

        WHEN e.equipment_id IS NULL
            THEN 'Equipment not found in silver_equipment'

    END AS reason

FROM bronze_dispatches d

LEFT JOIN silver_customers c
    ON TRIM(d.customer_id) = c.customer_id

LEFT JOIN silver_equipment e
    ON TRIM(d.equipment_id) = e.equipment_id

WHERE c.customer_id IS NULL
   OR e.equipment_id IS NULL;


#VALIDATE QUARANTINE COUNT
SELECT
    COUNT(*) AS quarantined_rows
FROM dq_dispatches;

#VALIDATE QUARANTINE REASONS
SELECT
    reason,
    COUNT(*) AS row_count
FROM dq_dispatches
GROUP BY reason;

#SHOW QUARANTINED RECORDS
SELECT *
FROM dq_dispatches
LIMIT 10;

#SILVER SERVICE LOG TABLE CREATION
USE gigavolt;
DROP TABLE IF EXISTS silver_dispatches;
CREATE TABLE silver_dispatches (
    dispatch_id VARCHAR(50) PRIMARY KEY,
    equipment_id VARCHAR(50) NOT NULL,
    dispatch_date DATE NOT NULL,
    technician VARCHAR(255),
    service_type VARCHAR(100) NOT NULL,
    hours_spent DECIMAL(10,2) NOT NULL,
    labor_cost DECIMAL(12,2) NOT NULL,
    resolution_summary TEXT,
    status VARCHAR(30) NOT NULL,

    CONSTRAINT fk_dispatch_equipment
        FOREIGN KEY (equipment_id)
        REFERENCES silver_equipment(equipment_id)
);

#LOAD CLEANED DATA INTO SILVER SERVICE LOGS
INSERT INTO silver_dispatches (
    dispatch_id,
    equipment_id,
    dispatch_date,
    technician,
    service_type,
    hours_spent,
    labor_cost,
    resolution_summary,
    status
)
SELECT

    #TRIM DISPATCH AND EQUIPMENT IDs

    TRIM(d.dispatch_id),

    TRIM(d.equipment_id),


    #CONVERT DISPATCH DATE TO DATE FORMAT

    CASE
        WHEN TRIM(d.dispatch_date) LIKE '%T%'
            THEN DATE(
                SUBSTRING_INDEX(
                    TRIM(d.dispatch_date),
                    'T',
                    1
                )
            )

        WHEN TRIM(d.dispatch_date)
             REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(d.dispatch_date),
                '%m-%d-%Y'
            )

        WHEN TRIM(d.dispatch_date)
             REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(d.dispatch_date),
                '%m/%d/%Y'
            )

        WHEN TRIM(d.dispatch_date)
             REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(d.dispatch_date),
                '%Y-%m-%d'
            )

        WHEN TRIM(d.dispatch_date)
             REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(d.dispatch_date),
                '%Y/%m/%d'
            )
    END,

    #CLEAN TECHNICIAN

    NULLIF(
        TRIM(
            REPLACE(
                REPLACE(d.technician, CHAR(13), ''),
                CHAR(10), ''
            )
        ),
        ''
    ),

    #CLEAN SERVICE TYPE
    TRIM(d.service_type),

    #CONVERT HOURS TO DECIMAL
    CAST(
        TRIM(d.hours_spent)
        AS DECIMAL(10,2)
    ),



    #REMOVE CURRENCY SYMBOLS AND CONVERT LABOR COST TO DECIMAL
    CAST(
        REGEXP_REPLACE(
            TRIM(d.labor_cost),
            '[^0-9.]',
            ''
        )
        AS DECIMAL(12,2)
    ),

    #REMOVE HTML AND CONTROL CHARACTERS FROM RESOLUTION
    NULLIF(
        TRIM(
            REGEXP_REPLACE(
                REPLACE(
                    REPLACE(
                        d.resolution_summary,
                        CHAR(13),
                        ''
                    ),
                    CHAR(10),
                    ''
                ),
                '<[^>]*>',
                ''
            )
        ),
        ''
    ),


    #REMOVE HIDDEN CHARACTERS AND STANDARDIZE STATUS

    LOWER(
        TRIM(
            REPLACE(
                REPLACE(
                    d.status,
                    CHAR(13),
                    ''
                ),
                CHAR(10),
                ''
            )
        )
    )

FROM bronze_dispatches d

#ONLY VALID CUSTOMER AND EQUIPMENT RELATIONSHIPS
INNER JOIN silver_equipment e
    ON TRIM(d.equipment_id) = e.equipment_id
INNER JOIN silver_customers c
    ON TRIM(d.customer_id) = c.customer_id;


#VALIDATE SILVER SERVICE LOGS
#1. ROW COUNT
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT dispatch_id) AS unique_dispatch_ids
FROM silver_dispatches;

#2. MISSING VALUES
SELECT
    SUM(dispatch_id IS NULL OR TRIM(dispatch_id) = '') AS missing_dispatch_id,
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(dispatch_date IS NULL) AS missing_dispatch_date,
    SUM(technician IS NULL OR TRIM(technician) = '') AS missing_technician,
    SUM(service_type IS NULL OR TRIM(service_type) = '') AS missing_service_type,
    SUM(hours_spent IS NULL) AS missing_hours_spent,
    SUM(labor_cost IS NULL) AS missing_labor_cost,
    SUM(resolution_summary IS NULL OR TRIM(resolution_summary) = '') AS missing_resolution_summary,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status
FROM silver_dispatches;

#3. EQUIPMENT FOREIGN KEY CHECK
SELECT COUNT(*) AS orphan_equipment_rows
FROM silver_dispatches d
LEFT JOIN silver_equipment e
    ON d.equipment_id = e.equipment_id
WHERE e.equipment_id IS NULL;

#4. DUPLICATE DISPATCH CHECK
SELECT
    dispatch_id,
    COUNT(*) AS row_count
FROM silver_dispatches
GROUP BY dispatch_id
HAVING COUNT(*) > 1;

#5. DATE RANGE
SELECT
    MIN(dispatch_date) AS earliest_dispatch,
    MAX(dispatch_date) AS latest_dispatch
FROM silver_dispatches;

#6. HOURS PROFILE
SELECT
    MIN(hours_spent) AS min_hours,
    MAX(hours_spent) AS max_hours,
    AVG(hours_spent) AS avg_hours
FROM silver_dispatches;

#7. LABOR COST PROFILE
SELECT
    MIN(labor_cost) AS min_labor_cost,
    MAX(labor_cost) AS max_labor_cost,
    AVG(labor_cost) AS avg_labor_cost
FROM silver_dispatches;

#8. STATUS VALUES
SELECT
    status,
    COUNT(*) AS row_count
FROM silver_dispatches
GROUP BY status
ORDER BY row_count DESC;

#9. HTML CHECK
SELECT
    SUM(resolution_summary REGEXP '<[^>]*>') AS remaining_html
FROM silver_dispatches;

#10. CONTROL CHARACTER CHECK
SELECT
    SUM(
        technician LIKE CONCAT('%', CHAR(13), '%')
        OR technician LIKE CONCAT('%', CHAR(10), '%')
    ) AS technician_control,

    SUM(
        resolution_summary LIKE CONCAT('%', CHAR(13), '%')
        OR resolution_summary LIKE CONCAT('%', CHAR(10), '%')
    ) AS resolution_control,

    SUM(
        status LIKE CONCAT('%', CHAR(13), '%')
        OR status LIKE CONCAT('%', CHAR(10), '%')
    ) AS status_control

FROM silver_dispatches;























-- ============================================================
-- WARRANTY CLAIMS DATASET
-- ============================================================
#CREATE BRONZE TABLE
USE gigavolt;
DROP TABLE IF EXISTS bronze_warranty_claims;
CREATE TABLE bronze_warranty_claims (
    source_row_id INT AUTO_INCREMENT PRIMARY KEY,
    claim_id VARCHAR(100),
    equipment_id VARCHAR(100),
    dispatch_id VARCHAR(100),
    part_id VARCHAR(100),
    claim_date VARCHAR(255),
    claim_amount VARCHAR(100),
    approved_amount VARCHAR(100),
    status VARCHAR(100),
    denial_reason TEXT,
    claim_notes TEXT
);

#LOAD DATA IN BRONZE TABLE
LOAD DATA INFILE '/var/lib/mysql-files/warranty_claims.csv'
INTO TABLE bronze_warranty_claims
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    claim_id,
    equipment_id,
    dispatch_id,
    part_id,
    claim_date,
    claim_amount,
    approved_amount,
    status,
    denial_reason,
    claim_notes
);

#PROFILING

#1. BASIC ROW COUNT
SELECT
    COUNT(*) AS total_rows
FROM bronze_warranty_claims;

#2. UNIQUE CLAIM IDs
SELECT
    COUNT(DISTINCT claim_id) AS unique_claim_ids
FROM bronze_warranty_claims;

#3. DUPLICATE CLAIM ROWS
SELECT
    COUNT(*) - COUNT(DISTINCT claim_id) AS duplicate_claim_id_rows
FROM bronze_warranty_claims;

#4. CLAIM IDs APPEARING MORE THAN ONCE
SELECT
    claim_id,
    COUNT(*) AS occurrences
FROM bronze_warranty_claims
GROUP BY claim_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, claim_id;

#5. MISSING VALUES
SELECT
    SUM(claim_id IS NULL OR TRIM(claim_id) = '') AS missing_claim_id,
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(dispatch_id IS NULL OR TRIM(dispatch_id) = '') AS missing_dispatch_id,
    SUM(part_id IS NULL OR TRIM(part_id) = '') AS missing_part_id,
    SUM(claim_date IS NULL OR TRIM(claim_date) = '') AS missing_claim_date,
    SUM(claim_amount IS NULL OR TRIM(claim_amount) = '') AS missing_claim_amount,
    SUM(approved_amount IS NULL OR TRIM(approved_amount) = '') AS missing_approved_amount,
    SUM(status IS NULL OR TRIM(status) = '') AS missing_status,
    SUM(denial_reason IS NULL OR TRIM(denial_reason) = '') AS missing_denial_reason,
    SUM(claim_notes IS NULL OR TRIM(claim_notes) = '') AS missing_claim_notes
FROM bronze_warranty_claims;

#6. ID FORMAT VALIDATION
SELECT
    SUM(claim_id NOT REGEXP '^CLM-[0-9]+$') AS invalid_claim_ids,

    SUM(equipment_id NOT REGEXP '^EQ-[0-9]+$') AS invalid_equipment_ids,

    SUM(
        dispatch_id IS NOT NULL
        AND TRIM(dispatch_id) <> ''
        AND dispatch_id NOT REGEXP '^DISP-[0-9]+$'
    ) AS invalid_dispatch_ids,

    SUM(
        part_id IS NOT NULL
        AND TRIM(part_id) <> ''
        AND part_id NOT REGEXP '^PRT-[0-9]+$'
    ) AS invalid_part_ids

FROM bronze_warranty_claims;


#7. CLAIM DATE FORMAT PROFILE
SELECT
    SUM(
        TRIM(claim_date)
        REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
    ) AS mm_dd_yyyy,

    SUM(
        TRIM(claim_date)
        REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
    ) AS mm_dd_yyyy_dash,

    SUM(
        TRIM(claim_date)
        REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
    ) AS yyyy_mm_dd_slash,

    SUM(
        TRIM(claim_date)
        REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    ) AS yyyy_mm_dd_dash,

    SUM(
        TRIM(claim_date) LIKE '%T%'
    ) AS iso_timestamp

FROM bronze_warranty_claims;

#8. CLAIM AMOUNT PROFILE
SELECT
    MIN(
        CAST(
            REGEXP_REPLACE(
                TRIM(claim_amount),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(10,2)
        )
    ) AS min_claim_amount,

    MAX(
        CAST(
            REGEXP_REPLACE(
                TRIM(claim_amount),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(10,2)
        )
    ) AS max_claim_amount,

    ROUND(
        AVG(
            CAST(
                REGEXP_REPLACE(
                    TRIM(claim_amount),
                    '[^0-9.]',
                    ''
                )
                AS DECIMAL(10,2)
            )
        ),
        2
    ) AS avg_claim_amount

FROM bronze_warranty_claims;

#9. APPROVED AMOUNT PROFILE
SELECT
    MIN(
        CASE
            WHEN approved_amount IS NOT NULL
                 AND TRIM(approved_amount) <> ''
            THEN CAST(
                REGEXP_REPLACE(
                    TRIM(approved_amount),
                    '[^0-9.]',
                    ''
                )
                AS DECIMAL(10,2)
            )
        END
    ) AS min_approved_amount,

    MAX(
        CASE
            WHEN approved_amount IS NOT NULL
                 AND TRIM(approved_amount) <> ''
            THEN CAST(
                REGEXP_REPLACE(
                    TRIM(approved_amount),
                    '[^0-9.]',
                    ''
                )
                AS DECIMAL(10,2)
            )
        END
    ) AS max_approved_amount,

    ROUND(
        AVG(
            CASE
                WHEN approved_amount IS NOT NULL
                     AND TRIM(approved_amount) <> ''
                THEN CAST(
                    REGEXP_REPLACE(
                        TRIM(approved_amount),
                        '[^0-9.]',
                        ''
                    )
                    AS DECIMAL(10,2)
                )
            END
        ),
        2
    ) AS avg_approved_amount

FROM bronze_warranty_claims;

#10. STATUS VALUES
SELECT
    LOWER(
        TRIM(
            REPLACE(
                REPLACE(status, CHAR(13), ''),
                CHAR(10), ''
            )
        )
    ) AS cleaned_status,
    COUNT(*) AS row_count
FROM bronze_warranty_claims
GROUP BY cleaned_status
ORDER BY row_count DESC;

#11. CURRENCY AND SYMBOL PROFILE
SELECT
    CASE
        WHEN claim_amount LIKE '%$%'
            THEN 'Dollar symbol'

        WHEN claim_amount LIKE '%USD%'
            THEN 'USD'

        ELSE 'Other'
    END AS amount_format,
    COUNT(*) AS row_count
FROM bronze_warranty_claims
GROUP BY amount_format;

#12. HTML TAG CHECK
SELECT
    SUM(claim_id REGEXP '<[^>]*>') AS claim_id_html,
    SUM(equipment_id REGEXP '<[^>]*>') AS equipment_id_html,
    SUM(dispatch_id REGEXP '<[^>]*>') AS dispatch_id_html,
    SUM(part_id REGEXP '<[^>]*>') AS part_id_html,
    SUM(denial_reason REGEXP '<[^>]*>') AS denial_reason_html,
    SUM(claim_notes REGEXP '<[^>]*>') AS claim_notes_html
FROM bronze_warranty_claims;

#13. LEADING AND TRAILING WHITESPACE
SELECT
    SUM(claim_id <> TRIM(claim_id)) AS claim_id_whitespace,
    SUM(equipment_id <> TRIM(equipment_id)) AS equipment_id_whitespace,
    SUM(dispatch_id <> TRIM(dispatch_id)) AS dispatch_id_whitespace,
    SUM(part_id <> TRIM(part_id)) AS part_id_whitespace,
    SUM(status <> TRIM(status)) AS status_whitespace,
    SUM(denial_reason <> TRIM(denial_reason)) AS denial_reason_whitespace,
    SUM(claim_notes <> TRIM(claim_notes)) AS claim_notes_whitespace
FROM bronze_warranty_claims;

#14. HIDDEN CONTROL CHARACTERS
SELECT
    SUM(
        claim_id LIKE CONCAT('%', CHAR(13), '%')
        OR claim_id LIKE CONCAT('%', CHAR(10), '%')
    ) AS claim_id_control_chars,

    SUM(
        status LIKE CONCAT('%', CHAR(13), '%')
        OR status LIKE CONCAT('%', CHAR(10), '%')
    ) AS status_control_chars,

    SUM(
        denial_reason LIKE CONCAT('%', CHAR(13), '%')
        OR denial_reason LIKE CONCAT('%', CHAR(10), '%')
    ) AS denial_reason_control_chars,

    SUM(
        claim_notes LIKE CONCAT('%', CHAR(13), '%')
        OR claim_notes LIKE CONCAT('%', CHAR(10), '%')
    ) AS claim_notes_control_chars

FROM bronze_warranty_claims;


#15. NEGATIVE MONETARY VALUES
SELECT
    SUM(
        CAST(
            REGEXP_REPLACE(
                TRIM(claim_amount),
                '[^0-9.-]',
                ''
            )
            AS DECIMAL(10,2)
        ) < 0
    ) AS negative_claim_amounts,

    SUM(
        CASE
            WHEN approved_amount IS NOT NULL
                 AND TRIM(approved_amount) <> ''
            THEN CAST(
                REGEXP_REPLACE(
                    TRIM(approved_amount),
                    '[^0-9.-]',
                    ''
                )
                AS DECIMAL(10,2)
            ) < 0
            ELSE 0
        END
    ) AS negative_approved_amounts

FROM bronze_warranty_claims;

#16. APPROVED AMOUNT GREATER THAN CLAIM AMOUNT
SELECT
    COUNT(*) AS approved_greater_than_claim
FROM bronze_warranty_claims
WHERE approved_amount IS NOT NULL
  AND TRIM(approved_amount) <> ''
  AND CAST(
        REGEXP_REPLACE(
            TRIM(approved_amount),
            '[^0-9.]',
            ''
        )
        AS DECIMAL(10,2)
      )
      >
      CAST(
        REGEXP_REPLACE(
            TRIM(claim_amount),
            '[^0-9.]',
            ''
        )
        AS DECIMAL(10,2)
      );

#17. EQUIPMENT FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_equipment
FROM bronze_warranty_claims w
LEFT JOIN silver_equipment e
    ON TRIM(w.equipment_id) = e.equipment_id
WHERE e.equipment_id IS NULL;

#18. DISPATCH FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_dispatches
FROM bronze_warranty_claims w
LEFT JOIN silver_dispatches d
    ON TRIM(w.dispatch_id) = d.dispatch_id
WHERE w.dispatch_id IS NOT NULL
  AND TRIM(w.dispatch_id) <> ''
  AND d.dispatch_id IS NULL;

#19. PARTS FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_parts
FROM bronze_warranty_claims w
LEFT JOIN silver_parts p
    ON TRIM(w.part_id) = p.part_id
WHERE w.part_id IS NOT NULL
  AND TRIM(w.part_id) <> ''
  AND p.part_id IS NULL;

#20. SAMPLE DIRTY WARRANTY CLAIM RECORDS
SELECT *
FROM bronze_warranty_claims
WHERE
    claim_id <> TRIM(claim_id)
    OR status <> TRIM(status)
    OR denial_reason REGEXP '<[^>]*>'
    OR claim_notes REGEXP '<[^>]*>'
    OR claim_amount LIKE '%$%'
    OR claim_amount LIKE '%USD%'
    OR approved_amount LIKE '%$%'
    OR approved_amount LIKE '%USD%'
LIMIT 10;

#SILVER WARRANTY CLAIM TABLE CREATION
USE gigavolt;

DROP TABLE IF EXISTS silver_warranty_claims;
CREATE TABLE silver_warranty_claims (
    claim_id VARCHAR(50) PRIMARY KEY,
    equipment_id VARCHAR(50) NOT NULL,
    dispatch_id VARCHAR(50),
    part_id VARCHAR(50),
    claim_date DATE NOT NULL,
    claim_amount DECIMAL(10,2) NOT NULL,
    approved_amount DECIMAL(10,2),
    status VARCHAR(30) NOT NULL,
    denial_reason TEXT,
    claim_notes TEXT,

    CONSTRAINT fk_claim_equipment
        FOREIGN KEY (equipment_id)
        REFERENCES silver_equipment(equipment_id),

    CONSTRAINT fk_claim_dispatch
        FOREIGN KEY (dispatch_id)
        REFERENCES silver_dispatches(dispatch_id),

    CONSTRAINT fk_claim_part
        FOREIGN KEY (part_id)
        REFERENCES silver_parts(part_id)
);

#LOAD CLEANED DATA INTO SILVER
INSERT INTO silver_warranty_claims (
    claim_id,
    equipment_id,
    dispatch_id,
    part_id,
    claim_date,
    claim_amount,
    approved_amount,
    status,
    denial_reason,
    claim_notes
)
SELECT

    #CLEAN CLAIM ID
    TRIM(w.claim_id),

    #CLEAN EQUIPMENT ID
    TRIM(w.equipment_id),

    #VALIDATE OPTIONAL DISPATCH RELATIONSHIP
    CASE
        WHEN w.dispatch_id IS NULL
             OR TRIM(w.dispatch_id) = ''
            THEN NULL

        WHEN EXISTS (
            SELECT 1
            FROM silver_dispatches d
            WHERE d.dispatch_id = TRIM(w.dispatch_id)
        )
            THEN TRIM(w.dispatch_id)

        ELSE NULL
    END,

    #VALIDATE OPTIONAL PART RELATIONSHIP

    CASE
        WHEN w.part_id IS NULL
             OR TRIM(w.part_id) = ''
            THEN NULL

        WHEN EXISTS (
            SELECT 1
            FROM silver_parts p
            WHERE p.part_id = TRIM(w.part_id)
        )
            THEN TRIM(w.part_id)

        ELSE NULL
    END,

    #CONVERT CLAIM DATE TO DATE FORMAT
    CASE
        WHEN TRIM(w.claim_date) LIKE '%T%'
            THEN DATE(
                SUBSTRING_INDEX(
                    TRIM(w.claim_date),
                    'T',
                    1
                )
            )

        WHEN TRIM(w.claim_date)
             REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(w.claim_date),
                '%m-%d-%Y'
            )

        WHEN TRIM(w.claim_date)
             REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN STR_TO_DATE(
                TRIM(w.claim_date),
                '%m/%d/%Y'
            )

        WHEN TRIM(w.claim_date)
             REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(w.claim_date),
                '%Y/%m/%d'
            )

        WHEN TRIM(w.claim_date)
             REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(
                TRIM(w.claim_date),
                '%Y-%m-%d'
            )
    END,

    #CONVERT CLAIM AMOUNT TO DECIMAL
    CAST(
        REGEXP_REPLACE(
            TRIM(w.claim_amount),
            '[^0-9.]',
            ''
        )
        AS DECIMAL(10,2)
    ),


    #CLEAN APPROVED AMOUNT AND PRESERVE MISSING VALUES
    CASE
        WHEN w.approved_amount IS NULL
             OR TRIM(
                    REPLACE(
                        REPLACE(
                            w.approved_amount,
                            CHAR(13),
                            ''
                        ),
                        CHAR(10),
                        ''
                    )
                ) = ''
            THEN NULL

        ELSE CAST(
            REGEXP_REPLACE(
                TRIM(
                    REPLACE(
                        REPLACE(
                            w.approved_amount,
                            CHAR(13),
                            ''
                        ),
                        CHAR(10),
                        ''
                    )
                ),
                '[^0-9.]',
                ''
            )
            AS DECIMAL(10,2)
        )
    END,

    #STANDARDIZE STATUS
    LOWER(
        TRIM(
            REPLACE(
                REPLACE(
                    w.status,
                    CHAR(13),
                    ''
                ),
                CHAR(10),
                ''
            )
        )
    ),

    #REMOVE HTML FROM DENIAL REASON
    NULLIF(
        TRIM(
            REGEXP_REPLACE(
                REPLACE(
                    REPLACE(
                        w.denial_reason,
                        CHAR(13),
                        ''
                    ),
                    CHAR(10),
                    ''
                ),
                '<[^>]*>',
                ''
            )
        ),
        ''
    ),


    #CLEAN CLAIM NOTES
    NULLIF(
        TRIM(
            REPLACE(
                REPLACE(
                    w.claim_notes,
                    CHAR(13),
                    ''
                ),
                CHAR(10),
                ''
            )
        ),
        ''
    )

FROM bronze_warranty_claims w

#VALIDATE REQUIRED EQUIPMENT RELATIONSHIP
INNER JOIN silver_equipment e
    ON TRIM(w.equipment_id) = e.equipment_id

#REMOVE DUPLICATE CLAIM IDs
WHERE w.source_row_id = (
    SELECT MAX(w2.source_row_id)
    FROM bronze_warranty_claims w2
    WHERE w2.claim_id = w.claim_id
);

#FINAL WARRANTY CLAIM VALIDATION
#1. ROW COUNT
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT claim_id) AS unique_claim_ids
FROM silver_warranty_claims;

#2. MISSING REQUIRED VALUES
SELECT
    SUM(claim_id IS NULL OR TRIM(claim_id) = '') AS missing_claim_id,
    SUM(equipment_id IS NULL OR TRIM(equipment_id) = '') AS missing_equipment_id,
    SUM(claim_date IS NULL) AS missing_claim_date,
    SUM(claim_amount IS NULL) AS missing_claim_amount
FROM silver_warranty_claims;

#3. EQUIPMENT FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_equipment
FROM silver_warranty_claims w
LEFT JOIN silver_equipment e
    ON w.equipment_id = e.equipment_id
WHERE e.equipment_id IS NULL;

#4. SERVICE LOG FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_dispatch
FROM silver_warranty_claims w
LEFT JOIN silver_dispatches s
    ON w.dispatch_id = s.dispatch_id
WHERE w.dispatch_id IS NOT NULL
  AND s.dispatch_id IS NULL;
#5. PART FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_parts
FROM silver_warranty_claims w
LEFT JOIN silver_parts p
    ON w.part_id = p.part_id
WHERE w.part_id IS NOT NULL
  AND p.part_id IS NULL;

#6. DUPLICATE CLAIM CHECK
SELECT
    claim_id,
    COUNT(*) AS row_count
FROM silver_warranty_claims
GROUP BY claim_id
HAVING COUNT(*) > 1;

#7. STATUS DISTRIBUTION
SELECT
    status,
    COUNT(*) AS row_count
FROM silver_warranty_claims
GROUP BY status
ORDER BY row_count DESC;

#8. DATE RANGE
SELECT
    MIN(claim_date) AS earliest_claim_date,
    MAX(claim_date) AS latest_claim_date
FROM silver_warranty_claims;

#9. HTML CHECK
SELECT
    SUM(
        denial_reason REGEXP '<[^>]*>'
        OR claim_notes REGEXP '<[^>]*>'
    ) AS rows_with_html
FROM silver_warranty_claims;

#10. CONTROL CHARACTER CHECK
SELECT
    SUM(
        status LIKE CONCAT('%', CHAR(13), '%')
        OR status LIKE CONCAT('%', CHAR(10), '%')
        OR denial_reason LIKE CONCAT('%', CHAR(13), '%')
        OR denial_reason LIKE CONCAT('%', CHAR(10), '%')
        OR claim_notes LIKE CONCAT('%', CHAR(13), '%')
        OR claim_notes LIKE CONCAT('%', CHAR(10), '%')
    ) AS rows_with_control_chars
FROM silver_warranty_claims;
















-- ============================================================
-- FINAL DATABASE VALIDATION
-- ============================================================
USE gigavolt;

#1. FINAL SILVER TABLE ROW COUNTS
SELECT
    'silver_customers' AS table_name,
    COUNT(*) AS row_count
FROM silver_customers

UNION ALL

SELECT
    'silver_equipment',
    COUNT(*)
FROM silver_equipment

UNION ALL

SELECT
    'silver_parts',
    COUNT(*)
FROM silver_parts

UNION ALL

SELECT
    'silver_dispatches',
    COUNT(*)
FROM silver_dispatches

UNION ALL

SELECT
    'silver_warranty_claims',
    COUNT(*)
FROM silver_warranty_claims;

#2. PRIMARY KEY DUPLICATE CHECKS
SELECT
    'Customers' AS table_name,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_keys
FROM silver_customers

UNION ALL

SELECT
    'Equipment',
    COUNT(*) - COUNT(DISTINCT equipment_id)
FROM silver_equipment

UNION ALL

SELECT
    'Parts',
    COUNT(*) - COUNT(DISTINCT part_id)
FROM silver_parts

UNION ALL

SELECT
    'Service Logs',
    COUNT(*) - COUNT(DISTINCT dispatch_id)
FROM silver_dispatches

UNION ALL

SELECT
    'Warranty Claims',
    COUNT(*) - COUNT(DISTINCT claim_id)
FROM silver_warranty_claims;

#3. EQUIPMENT → CUSTOMER FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_equipment_customers
FROM silver_equipment e
LEFT JOIN silver_customers c
    ON e.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

#4. SERVICE LOG → EQUIPMENT FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_service_equipment
FROM silver_dispatches s
LEFT JOIN silver_equipment e
    ON s.equipment_id = e.equipment_id
WHERE e.equipment_id IS NULL;

#5. WARRANTY CLAIM → EQUIPMENT FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_equipment
FROM silver_warranty_claims w
LEFT JOIN silver_equipment e
    ON w.equipment_id = e.equipment_id
WHERE e.equipment_id IS NULL;

#6. WARRANTY CLAIM → SERVICE LOG FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_dispatch
FROM silver_warranty_claims w
LEFT JOIN silver_dispatches s
    ON w.dispatch_id = s.dispatch_id
WHERE w.dispatch_id IS NOT NULL
  AND s.dispatch_id IS NULL;

#7. WARRANTY CLAIM → PART FOREIGN KEY CHECK
SELECT
    COUNT(*) AS orphan_claim_parts
FROM silver_warranty_claims w
LEFT JOIN silver_parts p
    ON w.part_id = p.part_id
WHERE w.part_id IS NOT NULL
  AND p.part_id IS NULL;

#8. REQUIRED NULL CHECK
SELECT
    SUM(customer_id IS NULL) AS customers_missing_id
FROM silver_customers;

SELECT
    SUM(equipment_id IS NULL) AS equipment_missing_id,
    SUM(customer_id IS NULL) AS equipment_missing_customer
FROM silver_equipment;

SELECT
    SUM(part_id IS NULL) AS parts_missing_id
FROM silver_parts;

SELECT
    SUM(dispatch_id IS NULL) AS service_logs_missing_id,
    SUM(equipment_id IS NULL) AS service_logs_missing_equipment
FROM silver_dispatches;

SELECT
    SUM(claim_id IS NULL) AS claims_missing_id,
    SUM(equipment_id IS NULL) AS claims_missing_equipment,
    SUM(claim_date IS NULL) AS claims_missing_date,
    SUM(claim_amount IS NULL) AS claims_missing_amount
FROM silver_warranty_claims;

#9. SHOW FINAL TABLE STRUCTURES
DESCRIBE silver_customers;
DESCRIBE silver_equipment;
DESCRIBE silver_parts;
DESCRIBE silver_dispatches;
DESCRIBE silver_warranty_claims;

#10. SHOW FOREIGN KEY RELATIONSHIPS
SELECT
    TABLE_NAME,
    CONSTRAINT_NAME,
    COLUMN_NAME,
    REFERENCED_TABLE_NAME,
    REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'gigavolt'
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME, CONSTRAINT_NAME;
