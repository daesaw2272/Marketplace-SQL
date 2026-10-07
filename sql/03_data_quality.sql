-- Olist marketplace: data quality checks
-- Run after loading. Each query states what a clean result looks like.

-- 1. Row counts per table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers',        COUNT(*) FROM sellers
UNION ALL SELECT 'products',       COUNT(*) FROM products
UNION ALL SELECT 'orders',         COUNT(*) FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM order_reviews
ORDER BY table_name;

-- 2. Order status mix. Revenue analysis uses delivered orders only.
SELECT order_status,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 3. Delivered orders with no delivery date (expect a handful)
SELECT COUNT(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- 4. Orders with no items (cancelled or unavailable orders usually)
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items i ON i.order_id = o.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

-- 5. Products whose category is missing or has no English translation
SELECT COALESCE(p.product_category_name, '(null)') AS category,
       COUNT(*)                                    AS products
FROM products p
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE t.product_category_name IS NULL
GROUP BY 1
ORDER BY products DESC;

-- 6. Item value against payment value per order (expect most within 1 cent)
WITH item_totals AS (
    SELECT order_id, SUM(price + freight_value) AS item_total
    FROM order_items GROUP BY order_id
),
payment_totals AS (
    SELECT order_id, SUM(payment_value) AS paid_total
    FROM order_payments GROUP BY order_id
)
SELECT COUNT(*)                                                        AS orders_compared,
       COUNT(*) FILTER (WHERE ABS(item_total - paid_total) <= 0.01)    AS matching,
       COUNT(*) FILTER (WHERE ABS(item_total - paid_total) >  0.01)    AS mismatched
FROM item_totals i
JOIN payment_totals p USING (order_id);

-- 7. Date range covered
SELECT MIN(order_purchase_timestamp)::date AS first_order,
       MAX(order_purchase_timestamp)::date AS last_order
FROM orders;
