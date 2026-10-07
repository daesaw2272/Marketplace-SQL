# Olist Marketplace SQL Analysis

Business analysis of a Brazilian online marketplace using PostgreSQL. The project builds a relational schema from eight raw CSV files, checks data quality, and answers nine commercial questions about revenue, customers, sellers and delivery.

## Business questions

| # | Question | SQL techniques |
|---|----------|----------------|
| 1 | How is revenue trending month to month? | `LAG`, running `SUM`, named `WINDOW` |
| 2 | Which product categories drive revenue? | Four table join, `RANK`, share of total |
| 3 | Do customers come back? | CTEs, cohort retention, `AGE`, `DATE_TRUNC` |
| 4 | Who are the most valuable customers? | RFM scoring with `NTILE`, `CASE` segments |
| 5 | Where is delivery failing, and does it hurt reviews? | `FILTER` aggregates, `HAVING` |
| 6 | Who are the top sellers in each state? | `DENSE_RANK` with `PARTITION BY` |
| 7 | How concentrated is seller revenue? | Cumulative share (Pareto) |
| 8 | How long until a customer's second order? | `ROW_NUMBER`, `LEAD`, `PERCENTILE_CONT` |
| 9 | How do customers pay? | `ARRAY_AGG`, conditional aggregates |

## Key findings

- Revenue is spread across many categories. The top category, health and beauty, holds about 9% of revenue and the top ten hold about 62%.
- Very few customers return. Monthly cohort retention stays under 1%, and about 97% of customers order once.
- Late delivery is the clearest driver of poor reviews. On-time orders average about 4.2 stars and late orders about 2.1 to 2.7.
- Seller revenue is concentrated. Fewer than 20% of sellers produce 80% of revenue.
- Credit cards account for about three quarters of orders, and around two thirds of those are paid in instalments.

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) from Kaggle: about 99K orders placed between September 2016 and September 2018.

Tables used: customers, sellers, products, category translation, orders, order items, order payments, order reviews. The geolocation file is not needed.

## Data model

```
customers 1 ── * orders 1 ── * order_items * ── 1 products * ── 0..1 category_translation
                    │                   * ── 1 sellers
                    ├── * order_payments
                    └── * order_reviews
```

Notes on the source data:

- `customer_id` is unique per order. `customer_unique_id` identifies the person, so customer counts and retention use that column.
- `review_id` repeats in the source file, so `order_reviews` has no primary key.
- Some products have no category or an untranslated one, so category joins use `LEFT JOIN` with `COALESCE`.

## How to run

Requires PostgreSQL 14 or later.

1. Download the dataset from Kaggle and put the CSV files in a `data` folder.
2. From the project folder:

```
createdb olist
psql -d olist -f sql/01_schema.sql
psql -d olist -f sql/02_load.sql
psql -d olist -f sql/03_data_quality.sql
psql -d olist -f sql/04_analysis.sql
```

## Project structure

```
olist-sql-analysis/
├── README.md
├── data/                     raw CSVs (not committed)
└── sql/
    ├── 01_schema.sql         tables, keys and constraints
    ├── 02_load.sql           CSV load and indexes
    ├── 03_data_quality.sql   seven data checks
    └── 04_analysis.sql       reusable view and nine business queries
```

## Assumptions

- Revenue is item price plus freight, for delivered orders only.
- An order is late when the delivery date is after the estimated delivery date.
- Monthly trends exclude 2016 and September 2018 because those months hold only a few orders.
