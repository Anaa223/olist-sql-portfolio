# Olist E-Commerce SQL Analysis

A relational database analysis project using Olist's public Brazilian e-commerce dataset, built to practice and demonstrate multi-table joins, foreign key design, and data quality investigation using PostgreSQL (via Supabase).

## Why this project

I wanted a portfolio piece that went beyond querying a single flat table. This project uses a real, messy, multi-table dataset (9 linked CSVs) to demonstrate schema design, referential integrity, and the kind of data quality judgement calls that come up in real analyst work, not just SQL syntax.

## Tools

- PostgreSQL (hosted on Supabase)
- Dataset: [Brazilian E-Commerce Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

## Schema

```
customers ──< orders ──< order_items >── products
                │                          │
                │                     product_category_name_translation
                ├──< order_payments
                └──< order_reviews

sellers ──< order_items
```

**Primary keys:**

| Table | Primary Key |
|---|---|
| customers | customer_id |
| orders | order_id |
| order_items | composite: order_id + order_item_id |
| products | product_id |
| sellers | seller_id |
| order_payments | composite: order_id + payment_sequential |
| order_reviews | review_id |
| product_category_name_translation | product_category_name |

**Foreign keys established:**
- `orders.customer_id` → `customers.customer_id`
- `order_items.product_id` → `products.product_id`
- `order_items.seller_id` → `sellers.seller_id`
- `order_payments.order_id` → `orders.order_id`
- `order_reviews.order_id` → `orders.order_id`

**Foreign key not enforced:** `order_items.order_id` → `orders.order_id` (see data quality notes below)

## Data Quality Findings

### 1. Incomplete source import on `orders`
Initial CSV import of `orders` consistently landed at ~98,600 rows against an expected ~99,441. Confirmed via row count checks and repeated clean re-imports that the shortfall was reproducible, not a one-off fluke. As a result, ~800 rows in `order_items` reference `order_id`s that don't exist in `orders`.

**Decision:** Rather than force a constraint the data doesn't support, I left the `order_items → orders` foreign key unenforced and documented the gap. In practice this means any `INNER JOIN` between these tables will silently exclude ~800 order_items rows (under 1% of the table), which is an acceptable tradeoff for this project but worth flagging to a stakeholder in a real production setting.

```sql
-- Quantify the orphaned rows
SELECT COUNT(*) AS orphaned_order_items
FROM order_items
WHERE order_id NOT IN (SELECT order_id FROM orders);
```

### 2. Zero-value payments in `order_payments` reflect two distinct scenarios, not one data error
Found 9 rows with `payment_value <= 0`. Initial assumption was a single data quality issue, but investigation revealed two distinct, legitimate patterns:

- **`payment_type = 'voucher'`, `order_status = 'delivered'`/`'shipped'`**: orders fully covered by voucher credit, so the monetary payment value is correctly 0. Not an error.
- **`payment_type = 'not_defined'`, `order_status = 'canceled'`**: orders where checkout was never completed, consistent with abandoned or failed transactions.

```sql
SELECT op.order_id, op.payment_type, op.payment_value, o.order_status
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE op.payment_value <= 0;
```

**Decision:** Both patterns are retained in the dataset. For any future revenue analysis, `canceled` orders will be excluded, and voucher-covered orders will be treated as valid completed sales despite their 0 monetary payment value.

## Business Questions & Analysis

*(To be added as queries are finalized)*

1. Revenue by product category
2. Top sellers by revenue and order volume
3. Delivery time vs review score relationship
4. Payment type breakdown by order value tier
5. Full funnel: customer state → product category → revenue (multi-table join)
6. Repeat customer analysis (window function)

## Notes on Methodology

This project intentionally documents data quality findings as they were discovered, including a couple of dead ends and revised assumptions, rather than presenting only a clean final result. This reflects how real analysis actually happens.
