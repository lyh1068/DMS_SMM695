CREATE SCHEMA IF NOT EXISTS ssc;

CREATE TABLE IF NOT EXISTS ssc.dim_package (
    package_key BIGSERIAL PRIMARY KEY,
    package_name TEXT NOT NULL,
    normalized_package_name TEXT NOT NULL UNIQUE,
    author_email TEXT NULL
);
