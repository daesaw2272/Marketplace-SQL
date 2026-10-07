\copy customers            FROM 'data/olist_customers_dataset.csv'             CSV HEADER
\copy sellers              FROM 'data/olist_sellers_dataset.csv'               CSV HEADER
\copy category_translation FROM 'data/product_category_name_translation.csv'   CSV HEADER
\copy products             FROM 'data/olist_products_dataset.csv'              CSV HEADER
\copy orders               FROM 'data/olist_orders_dataset.csv'                CSV HEADER
\copy order_items          FROM 'data/olist_order_items_dataset.csv'           CSV HEADER
\copy order_payments       FROM 'data/olist_order_payments_dataset.csv'        CSV HEADER
\copy order_reviews        FROM 'data/olist_order_reviews_dataset.csv'     CSV HEADER

CREATE INDEX idx_orders_customer      ON orders (customer_id);
CREATE INDEX idx_orders_purchase_ts   ON orders (order_purchase_timestamp);
CREATE INDEX idx_items_product        ON order_items (product_id);
CREATE INDEX idx_items_seller         ON order_items (seller_id);
CREATE INDEX idx_reviews_order        ON order_reviews (order_id);
CREATE INDEX idx_customers_unique     ON customers (customer_unique_id);

\data\olist_order_reviews_dataset.csv