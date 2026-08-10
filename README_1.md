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

## Key Findings Summary

- **Delivery speed strongly predicts satisfaction**: 1-star reviews average 20.4 delivery days vs 10.7 for 5-star reviews, a near-monotonic relationship (Q3)
- **Revenue is geographically concentrated**: São Paulo occupies 9 of the top 10 state-category revenue combinations (Q5)
- **Two distinct revenue strategies emerge at both category and seller level**: high-volume/lower-price vs low-volume/high-price, with computers as an extreme example (181 orders, R$1,098 avg price) (Q1, Q2)
- **Payment method is stable across order value**: credit card holds ~65-70% share regardless of order size (Q4)
- **Only ~12% of customers are repeat buyers**, suggesting retention is a more promising lever than average order value (Q6)

## Business Questions & Analysis

### 1. Revenue by product category

```sql
SELECT
  COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
  COUNT(DISTINCT oi.order_id) AS num_orders,
  ROUND(SUM(oi.price)::numeric, 2) AS total_revenue,
  ROUND(AVG(oi.price)::numeric, 2) AS avg_item_price
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
  ON p.product_category_name = t.product_category_name
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status != 'canceled'
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
ORDER BY total_revenue DESC
LIMIT 20;
```

**Top results:**

| Category | Orders | Revenue (R$) | Avg Item Price (R$) |
|---|---|---|---|
| health_beauty | 8,800 | 1,255,695.13 | 130.34 |
| watches_gifts | 5,604 | 1,198,185.21 | 200.70 |
| bed_bath_table | 9,399 | 1,035,964.06 | 93.36 |
| sports_leisure | 7,673 | 979,740.92 | 114.06 |
| computers | 181 | 222,963.13 | 1,098.34 |

**Interpretation:** health_beauty leads on total revenue with high order volume, while watches_gifts nearly matches it despite far fewer orders, driven by a much higher average item price. Categories split into two clear patterns: high-volume/lower-price (bed_bath_table, health_beauty, sports_leisure) versus low-volume/high-price (computers, watches_gifts). Computers is a notable outlier: only 181 orders but an average item price of R$1,098, more than 5x any other category, consistent with computers being inherently higher-ticket items. This suggests revenue strategy should differ by category: volume-driven categories benefit from broad reach, while high-ticket categories like computers may benefit more from targeted, higher-touch sales approaches.

### 2. Top sellers by revenue and order volume

```sql
SELECT
  oi.seller_id,
  COUNT(DISTINCT oi.order_id) AS num_orders,
  ROUND(SUM(oi.price)::numeric, 2) AS total_revenue,
  ROUND(AVG(oi.price)::numeric, 2) AS avg_item_price
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_status != 'canceled'
GROUP BY oi.seller_id
ORDER BY total_revenue DESC
LIMIT 15;
```

**Top results:**

| Seller ID | Orders | Revenue (R$) | Avg Item Price (R$) |
|---|---|---|---|
| 4869f7a5... | 1,131 | 229,237.63 | 198.47 |
| 53243585... | 358 | 222,776.05 | 543.36 |
| 4a3ca931... | 1,804 | 200,326.12 | 100.92 |
| fa1c13f2... | 584 | 192,842.13 | 329.64 |
| 6560211a... | 1,847 | 122,776.83 | 60.63 |

**Interpretation:** The same volume-vs-value pattern from Q1 shows up at the seller level. Seller `53243585...` generates nearly as much total revenue as the top seller (`4869f7a5...`) with roughly a third of the order count, driven by a much higher average item price (R$543.36 vs R$198.47). This suggests sellers succeed through two different strategies: high-volume/lower-price or low-volume/high-price, mirroring the category-level pattern in Q1.

### 3. Delivery time vs review score relationship

```sql
SELECT
  r.review_score,
  COUNT(*) AS num_orders,
  ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::timestamp - o.order_purchase_timestamp::timestamp)) / 86400)::numeric, 1) AS avg_delivery_days
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;
```

**Results:**

| Review Score | Orders | Avg Delivery Days |
|---|---|---|
| 1 | 269 | 20.4 |
| 2 | 81 | 19.2 |
| 3 | 235 | 14.2 |
| 4 | 518 | 12.2 |
| 5 | 1,710 | 10.7 |

**Interpretation:** A strong, near-monotonic relationship between delivery speed and customer satisfaction. 1-star reviews average 20.4 delivery days, roughly double the 10.7 days seen on 5-star reviews, and every step down in review score corresponds to a step up in delivery time with no exceptions. This is one of the clearest signals in the dataset and would be a strong candidate for a stakeholder-facing recommendation: delivery speed appears to be a primary driver of customer satisfaction.

**Data quality note:** this query initially failed with a type error (`operator does not exist: text - timestamp with time zone`), revealing that at least one date column had imported as `text` rather than a proper timestamp type. Resolved with explicit `::timestamp` casts. Worth checking column types early in future imports rather than assuming CSV import inferred them correctly.

### 4. Payment type breakdown by order value tier

```sql
WITH order_totals AS (
  SELECT
    o.order_id,
    o.order_status,
    SUM(op.payment_value) AS order_total,
    CASE
      WHEN SUM(op.payment_value) < 50 THEN 'Under R$50'
      WHEN SUM(op.payment_value) < 150 THEN 'R$50-150'
      WHEN SUM(op.payment_value) < 300 THEN 'R$150-300'
      ELSE 'R$300+'
    END AS value_tier
  FROM orders o
  JOIN order_payments op ON o.order_id = op.order_id
  WHERE o.order_status != 'canceled'
  GROUP BY o.order_id, o.order_status
)
SELECT
  ot.value_tier,
  op.payment_type,
  COUNT(*) AS num_payments,
  ROUND(AVG(ot.order_total)::numeric, 2) AS avg_order_value
FROM order_totals ot
JOIN order_payments op ON ot.order_id = op.order_id
GROUP BY ot.value_tier, op.payment_type
ORDER BY ot.value_tier, num_payments DESC;
```

**Results:**

| Value Tier | Payment Type | Payments | Avg Order Value (R$) |
|---|---|---|---|
| Under R$50 | credit_card | 11,968 | 37.02 |
| R$50-150 | credit_card | 38,214 | 93.66 |
| R$150-300 | credit_card | 17,677 | 203.20 |
| R$300+ | credit_card | 8,492 | 603.40 |

*(boleto, voucher, and debit_card follow at lower volumes in every tier, see full query output)*

**Interpretation:** Credit card is the dominant payment method across every value tier, consistently around 65-70% of payments regardless of order size. Notably, the relative distribution of payment types barely shifts between the cheapest and most expensive order tiers, customers don't appear to switch payment methods based on order value. This is a useful non-finding: payment method choice seems to be a stable customer preference rather than something driven by transaction size.

### 5. Full funnel: customer state → product category → revenue (multi-table join)

```sql
SELECT
  c.customer_state,
  COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
  COUNT(DISTINCT oi.order_id) AS num_orders,
  ROUND(SUM(oi.price)::numeric, 2) AS total_revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
  ON p.product_category_name = t.product_category_name
WHERE o.order_status != 'canceled'
GROUP BY c.customer_state, COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
ORDER BY total_revenue DESC
LIMIT 20;
```

**Top results:**

| State | Category | Orders | Revenue (R$) |
|---|---|---|---|
| SP | bed_bath_table | 4,405 | 477,794.20 |
| SP | health_beauty | 3,767 | 460,474.09 |
| SP | watches_gifts | 2,124 | 431,119.29 |
| RJ | watches_gifts | 815 | 183,931.50 |
| MG | health_beauty | 1,009 | 157,433.32 |

**Interpretation:** São Paulo (SP) dominates the dataset, occupying 9 of the top 10 state-category combinations, with its leading category alone outproducing most other states' total revenue. Rio de Janeiro (RJ) and Minas Gerais (MG) appear starting around rank 10, at roughly a third to a half of SP's category-level revenue. This is consistent with SP being Brazil's largest and most economically concentrated state, but it also highlights a geographic concentration risk worth flagging to a stakeholder: a large share of revenue is dependent on a single region.

### 6. Repeat customer analysis (window function)

```sql
WITH customer_order_counts AS (
  SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp,
    COUNT(o.order_id) OVER (PARTITION BY c.customer_unique_id) AS total_orders,
    SUM(oi.price) OVER (PARTITION BY c.customer_unique_id) AS customer_lifetime_value
  FROM customers c
  JOIN orders o ON c.customer_id = o.customer_id
  JOIN order_items oi ON o.order_id = oi.order_id
  WHERE o.order_status != 'canceled'
)
SELECT
  CASE WHEN total_orders = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
  COUNT(DISTINCT customer_unique_id) AS num_customers,
  ROUND(AVG(customer_lifetime_value)::numeric, 2) AS avg_lifetime_value
FROM customer_order_counts
GROUP BY CASE WHEN total_orders = 1 THEN 'One-time' ELSE 'Repeat' END;
```

**Results:**

| Customer Type | Customers | Avg Lifetime Value (R$) |
|---|---|---|
| One-time | 83,184 | 131.33 |
| Repeat | 11,805 | 256.18 |

**Interpretation:** Only about 12% of customers (11,805 of 94,989) are repeat buyers. Their average lifetime value (R$256.18) is roughly double that of one-time customers, but this figure represents total spend summed across all their orders, not a higher per-order value, so it shouldn't be read as "repeat customers spend twice as much per purchase." The more notable finding is the retention rate itself: with repeat purchase behaviour this low, customer retention looks like a stronger lever for revenue growth than increasing average order value.

**Schema note:** this query uses `customer_unique_id` rather than `customer_id` for identifying repeat customers. Olist's schema assigns a new `customer_id` per order, so `customer_id` alone would incorrectly treat every order as a different person. `customer_unique_id` is the correct person-level identifier for this kind of analysis.

## Notes on Methodology

This project intentionally documents data quality findings as they were discovered, including a couple of dead ends and revised assumptions, rather than presenting only a clean final result. This reflects how real analysis actually happens.
