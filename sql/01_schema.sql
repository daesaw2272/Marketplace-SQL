-- Olist marketplace: schema
-- PostgreSQL 14+
-- Run: psql -d olist -f sql/01_schema.sql

DROP TABLE IF EXISTS order_reviews, order_payments, order_items, orders,
                     products, sellers, customers, category_translation CASCADE;

CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,      -- one per order
    customer_unique_id       TEXT NOT NULL,         -- the actual person
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           CHAR(2)
);

CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           CHAR(2)
);

CREATE TABLE category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

-- Column names keep the spelling used in the source files ("lenght").
CREATE TABLE products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,                -- can be NULL or untranslated
    product_name_lenght        INT,
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           NUMERIC,
    product_length_cm          NUMERIC,
    product_height_cm          NUMERIC,
    product_width_cm           NUMERIC
);

CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL REFERENCES customers (customer_id),
    order_status                  TEXT NOT NULL,
    order_purchase_timestamp      TIMESTAMP NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE order_items (
    order_id            TEXT NOT NULL REFERENCES orders (order_id),
    order_item_id       INT  NOT NULL,
    product_id          TEXT NOT NULL REFERENCES products (product_id),
    seller_id           TEXT NOT NULL REFERENCES sellers (seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value       NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id             TEXT NOT NULL REFERENCES orders (order_id),
    payment_sequential   INT  NOT NULL,
    payment_type         TEXT NOT NULL,
    payment_installments INT,
    payment_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id repeats in the source data, so there is no primary key here.
CREATE TABLE order_reviews (
    review_id               TEXT NOT NULL,
    order_id                TEXT NOT NULL REFERENCES orders (order_id),
    review_score            INT  NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);
