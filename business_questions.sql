-- =====================================================
-- Olist E-Commerce SQL Analysis
-- Business Question Queries
-- =====================================================

-- Q1: Revenue by product category
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


-- Q2: Top sellers by revenue and order volume
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


-- Q3: Delivery time vs review score relationship
-- Note: order_purchase_timestamp / order_delivered_customer_date imported as text,
-- required explicit ::timestamp casts for date arithmetic.
SELECT
  r.review_score,
  COUNT(*) AS num_orders,
  ROUND(AVG(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::timestamp - o.order_purchase_timestamp::timestamp)) / 86400)::numeric, 1) AS avg_delivery_days
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;


-- Q4: Payment type breakdown by order value tier
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


-- Q5: Full funnel - customer state -> product category -> revenue (4-table join)
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


-- Q6: Repeat customer analysis (window function)
-- Note: uses customer_unique_id, not customer_id, since Olist assigns a new
-- customer_id per order. customer_unique_id is the true person-level identifier.
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
