-- Olist marketplace: business analysis
-- Revenue = item price + freight, delivered orders only.

-- Reusable base: one row per delivered order
CREATE OR REPLACE VIEW v_delivered_orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       (o.order_delivered_customer_date > o.order_estimated_delivery_date) AS is_late,
       i.revenue,
       i.items
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN (
    SELECT order_id,
           SUM(price + freight_value) AS revenue,
           COUNT(*)                   AS items
    FROM order_items
    GROUP BY order_id
) i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered';


-- Q1. How is revenue trending month to month?
-- Window functions: LAG for growth, running SUM for cumulative revenue.
WITH monthly AS (
    SELECT order_month,
           COUNT(*)               AS orders,
           SUM(revenue)           AS revenue,
           ROUND(AVG(revenue), 2) AS avg_order_value
    FROM v_delivered_orders
    -- 2016 and September 2018 hold only a few orders, so they distort growth rates
    WHERE order_month >= DATE '2017-01-01'
      AND order_month <  DATE '2018-09-01'
    GROUP BY order_month
)
SELECT order_month,
       orders,
       revenue,
       avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w) / NULLIF(LAG(revenue) OVER w, 0), 1) AS mom_growth_pct,
       SUM(revenue) OVER (ORDER BY order_month)                                            AS running_revenue
FROM monthly
WINDOW w AS (ORDER BY order_month)
ORDER BY order_month;


-- Q2. Which product categories drive revenue?
-- Four table join, share of total with SUM() OVER (), RANK.
WITH category_revenue AS (
    SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
           SUM(i.price + i.freight_value) AS revenue,
           COUNT(DISTINCT i.order_id)     AS orders
    FROM order_items i
    JOIN orders o   ON o.order_id = i.order_id AND o.order_status = 'delivered'
    JOIN products p ON p.product_id = i.product_id
    LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    GROUP BY 1
)
SELECT RANK() OVER (ORDER BY revenue DESC)                                      AS revenue_rank,
       category,
       revenue,
       orders,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)                         AS pct_of_revenue,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 2) AS cumulative_pct
FROM category_revenue
ORDER BY revenue DESC
LIMIT 15;


-- Q3. Do customers come back? Monthly cohort retention.
-- Cohort = month of first purchase. Retention = share who order again N months later.
WITH first_order AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM v_delivered_orders
    GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT d.customer_unique_id,
           f.cohort_month,
           (EXTRACT(YEAR  FROM AGE(d.order_month, f.cohort_month)) * 12
          + EXTRACT(MONTH FROM AGE(d.order_month, f.cohort_month)))::int AS months_since_first
    FROM v_delivered_orders d
    JOIN first_order f USING (customer_unique_id)
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers
    FROM first_order
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       s.customers                                                 AS cohort_customers,
       a.months_since_first,
       COUNT(*)                                                    AS active_customers,
       ROUND(100.0 * COUNT(*) / s.customers, 2)                    AS retention_pct
FROM activity a
JOIN cohort_size s USING (cohort_month)
WHERE a.months_since_first BETWEEN 0 AND 6
  AND a.cohort_month >= DATE '2017-01-01'
GROUP BY a.cohort_month, s.customers, a.months_since_first
ORDER BY a.cohort_month, a.months_since_first;


-- Q4. Who are the most valuable customers? RFM segmentation.
-- NTILE scores recency, frequency and monetary value from 1 to 5.
WITH snapshot AS (
    SELECT MAX(order_purchase_timestamp) + INTERVAL '1 day' AS as_of
    FROM v_delivered_orders
),
rfm AS (
    SELECT d.customer_unique_id,
           EXTRACT(DAY FROM (s.as_of - MAX(d.order_purchase_timestamp)))::int AS recency_days,
           COUNT(*)                                                           AS frequency,
           SUM(d.revenue)                                                     AS monetary
    FROM v_delivered_orders d
    CROSS JOIN snapshot s
    GROUP BY d.customer_unique_id, s.as_of
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- 5 = most recent
           NTILE(5) OVER (ORDER BY monetary)          AS m_score    -- 5 = highest spend
    FROM rfm
),
segmented AS (
    SELECT *,
           CASE
               WHEN frequency >= 2 AND r_score >= 4 THEN 'Loyal and recent'
               WHEN frequency >= 2                  THEN 'Repeat, lapsing'
               WHEN r_score >= 4 AND m_score >= 4   THEN 'New high spender'
               WHEN r_score >= 4                    THEN 'New'
               WHEN r_score <= 2 AND m_score >= 4   THEN 'High value at risk'
               WHEN r_score <= 2                    THEN 'Lost'
               ELSE 'Cooling'
           END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                             AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_customers,
       ROUND(AVG(recency_days))                             AS avg_recency_days,
       ROUND(AVG(frequency), 2)                             AS avg_orders,
       ROUND(AVG(monetary), 2)                              AS avg_spend,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_of_revenue
FROM segmented
GROUP BY segment
ORDER BY pct_of_revenue DESC;


-- Q5. Where is delivery failing, and does it hurt reviews?
-- FILTER clause for conditional aggregates; HAVING to drop tiny states.
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT d.customer_state,
       COUNT(*)                                                             AS orders,
       ROUND(AVG(EXTRACT(EPOCH FROM (d.order_delivered_customer_date - d.order_purchase_timestamp)) / 86400), 1) AS avg_delivery_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.is_late) / COUNT(*), 2)       AS late_pct,
       ROUND(AVG(r.review_score) FILTER (WHERE NOT d.is_late), 2)           AS avg_review_on_time,
       ROUND(AVG(r.review_score) FILTER (WHERE d.is_late), 2)               AS avg_review_late
FROM v_delivered_orders d
LEFT JOIN order_review r USING (order_id)
WHERE d.order_delivered_customer_date IS NOT NULL
GROUP BY d.customer_state
HAVING COUNT(*) >= 500
ORDER BY late_pct DESC;


-- Q6. Who are the top sellers in each state?
-- DENSE_RANK partitioned by state, plus each seller's share of state revenue.
WITH seller_revenue AS (
    SELECT s.seller_state,
           s.seller_id,
           SUM(i.price + i.freight_value) AS revenue,
           COUNT(DISTINCT i.order_id)     AS orders
    FROM order_items i
    JOIN orders o  ON o.order_id = i.order_id AND o.order_status = 'delivered'
    JOIN sellers s ON s.seller_id = i.seller_id
    GROUP BY s.seller_state, s.seller_id
),
ranked AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC)        AS state_rank,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY seller_state), 2)  AS pct_of_state_revenue,
           COUNT(*) OVER (PARTITION BY seller_state)                                  AS sellers_in_state
    FROM seller_revenue
)
SELECT seller_state, state_rank, seller_id, revenue, orders, pct_of_state_revenue, sellers_in_state
FROM ranked
WHERE state_rank <= 3
  AND sellers_in_state >= 20
ORDER BY seller_state, state_rank;


-- Q7. How concentrated is seller revenue? (Pareto)
-- What share of sellers produces 80% of revenue.
WITH seller_revenue AS (
    SELECT i.seller_id, SUM(i.price + i.freight_value) AS revenue
    FROM order_items i
    JOIN orders o ON o.order_id = i.order_id AND o.order_status = 'delivered'
    GROUP BY i.seller_id
),
cumulative AS (
    SELECT seller_id,
           revenue,
           SUM(revenue) OVER (ORDER BY revenue DESC, seller_id) / SUM(revenue) OVER () AS cumulative_share,
           ROW_NUMBER() OVER (ORDER BY revenue DESC, seller_id)                        AS seller_rank,
           COUNT(*) OVER ()                                                            AS total_sellers
    FROM seller_revenue
)
SELECT MIN(seller_rank)                                      AS sellers_for_80pct_revenue,
       MAX(total_sellers)                                    AS total_sellers,
       ROUND(100.0 * MIN(seller_rank) / MAX(total_sellers), 2) AS pct_of_sellers
FROM cumulative
WHERE cumulative_share >= 0.80;


-- Q8. How long until a customer's second order?
-- ROW_NUMBER and LEAD across each customer's order history.
WITH sequenced AS (
    SELECT customer_unique_id,
           order_purchase_timestamp,
           ROW_NUMBER() OVER w AS order_number,
           LEAD(order_purchase_timestamp) OVER w AS next_order_at
    FROM v_delivered_orders
    WINDOW w AS (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp)
),
gaps AS (
    SELECT EXTRACT(EPOCH FROM (next_order_at - order_purchase_timestamp)) / 86400 AS days_to_second
    FROM sequenced
    WHERE order_number = 1 AND next_order_at IS NOT NULL
)
SELECT COUNT(*)                                                             AS repeat_customers,
       ROUND(AVG(days_to_second)::numeric, 1)                               AS avg_days,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_second))::numeric, 1) AS median_days,
       COUNT(*) FILTER (WHERE days_to_second <= 30)                         AS within_30_days,
       COUNT(*) FILTER (WHERE days_to_second >  180)                        AS after_180_days
FROM gaps;


-- Q9. How do customers pay, and does it change basket size?
WITH order_payment AS (
    SELECT order_id,
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS main_payment_type,
           MAX(payment_installments)                                AS installments,
           SUM(payment_value)                                       AS paid
    FROM order_payments
    GROUP BY order_id
)
SELECT main_payment_type,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_orders,
       ROUND(AVG(paid), 2)                                 AS avg_order_value,
       ROUND(AVG(installments), 1)                         AS avg_installments,
       ROUND(100.0 * COUNT(*) FILTER (WHERE installments > 1) / COUNT(*), 1) AS pct_using_installments
FROM order_payment p
JOIN orders o ON o.order_id = p.order_id AND o.order_status = 'delivered'
GROUP BY main_payment_type
ORDER BY orders DESC;
