-- Reference definition. The loader creates three uniquely named tables per run.
-- Do not run this separately unless intentionally creating an independent example.
CREATE TABLE chunks_example_m8 (
    chunk_id CHAR(64) CHARACTER SET ascii PRIMARY KEY,
    source_file TEXT NOT NULL,
    source_type VARCHAR(32) NOT NULL,
    page_number INT NOT NULL,
    chunk_index INT NOT NULL,
    token_count INT NOT NULL,
    chunk_text LONGTEXT NOT NULL,
    metadata_json JSON NOT NULL,
    embedding VECTOR(384) NOT NULL,
    VECTOR INDEX vec_idx (embedding) M=8 DISTANCE=cosine
) ENGINE=InnoDB;
-- The application binds a 384-number JSON array to the parameter below.
-- SET SESSION mhnsw_ef_search=40;
-- SELECT SQL_NO_CACHE chunk_id, source_file, page_number, chunk_text,
-- VEC_DISTANCE_COSINE(embedding,VEC_FromText(?)) AS distance
-- FROM chunks_example_m8 ORDER BY distance LIMIT 5;
