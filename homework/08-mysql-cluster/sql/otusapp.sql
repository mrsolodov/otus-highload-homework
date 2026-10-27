-- MySQL equivalent of homework/07-highload-web's PostgreSQL requests table.
CREATE DATABASE IF NOT EXISTS otusapp;
CREATE TABLE IF NOT EXISTS otusapp.requests (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    backend VARCHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB;
