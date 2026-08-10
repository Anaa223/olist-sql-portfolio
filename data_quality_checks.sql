-- =====================================================
-- Olist E-Commerce SQL Analysis
-- Data Quality Investigation Queries
-- =====================================================

-- Finding 1: Orphaned rows in order_items
-- orders table consistently imported ~800 rows short of the expected ~99,441.
-- Result: order_items has rows referencing order_id values that don't exist in orders.
-- Decision: left the order_items -> orders foreign key unenforced, documented the gap.
SELECT COUNT(*) AS orphaned_order_items
FROM order_items
WHERE order_id NOT IN (SELECT order_id FROM orders);


-- Finding 2: Zero-value payments in order_payments
-- Investigated 9 rows with payment_value <= 0. Found two distinct legitimate patterns:
--   1. payment_type = 'voucher', order delivered/shipped -> order fully covered by voucher credit
--   2. payment_type = 'not_defined', order canceled -> failed/abandoned checkout
SELECT op.order_id, op.payment_type, op.payment_value, o.order_status
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE op.payment_value <= 0;


-- Supporting checks used during investigation

-- Row counts to confirm the orders shortfall was reproducible
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM order_items;
SELECT COUNT(DISTINCT order_id) FROM order_items;

-- Duplicate checks on composite keys before applying constraints
SELECT order_id, order_item_id, COUNT(*)
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

SELECT order_id, payment_sequential, COUNT(*)
FROM order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- Duplicate order_id check on order_reviews (some orders have multiple review rows)
SELECT order_id, COUNT(*) AS review_count
FROM order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY review_count DESC;

-- Payment type distribution, useful context ahead of Q4
SELECT payment_type, COUNT(*) AS num_payments, ROUND(AVG(payment_value)::numeric, 2) AS avg_value
FROM order_payments
GROUP BY payment_type
ORDER BY num_payments DESC;
