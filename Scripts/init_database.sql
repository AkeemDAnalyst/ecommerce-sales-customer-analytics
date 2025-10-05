-- Create Database
CREATE DATABASE Ecommerce_Analytics
GO
USE Ecommerce_Analytics
GO

-- Create Staging schema to organize raw imported tables
CREATE SCHEMA stg

-- Create Staging of copying raw data
SELECT * INTO stg.orders FROM df_Orders
SELECT * INTO stg.customers FROM df_Customers
SELECT * INTO stg.products FROM df_Products
SELECT * INTO stg.payments FROM df_Payments
SELECT * INTO stg.orderitems FROM df_OrderItems

/*===================================================================================================
-- Step 1: Create a Clean View for Customer
-- Purpose: Standardize Customer Data and generate numeric keys
==================================================================================================*/
-- Drop the view if it already exists (to avoid errors when re-running)
IF OBJECT_ID ( 'VW_Customers_clean', 'V') IS NOT NULL
	DROP VIEW VW_Customers_clean

-- Create the clean view
CREATE VIEW VW_Customers_clean AS 
Select 
	ROW_NUMBER() OVER (ORDER BY customer_id) AS Customer_key,
	customer_id,
	customer_zip_code_prefix,
	TRIM(customer_city) AS Customer_city,
	UPPER(customer_state) AS customer_state
	FROM stg.customers
	WHERE customer_id IS NOT NULL

	-- Drop the view if it already exists (to avoid errors when re-running)
IF OBJECT_ID ( 'VW_Orderitems_clean', 'V') IS NOT NULL
	DROP VIEW VW_Orderitems_clean

-- Create the clean view
CREATE VIEW VW_Orderitems_clean AS 
Select 
	ROW_NUMBER() OVER (ORDER BY order_id) AS order_key,
	ROW_NUMBER() OVER (ORDER BY product_id) AS product_key,
	ROW_NUMBER() OVER (ORDER BY seller_id) AS seller_key,
	order_id,
	product_id,
	seller_id,
	price,
	shipping_charges
	FROM stg.orderitems
	WHERE order_id IS NOT NULL AND product_id IS NOT NULL  AND seller_id IS NOT NULL

-- Drop the view if it already exists (to avoid errors when re-running)
IF OBJECT_ID ( 'VW_Orders_clean', 'V') IS NOT NULL
	DROP VIEW VW_Orders_clean

-- Create the clean view
CREATE VIEW VW_Orders_clean AS 
Select 
	ROW_NUMBER() OVER (ORDER BY order_id) AS order_key,
	ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_key,
	order_id,
	customer_id,
	CAST(order_purchase_timestamp AS DATETIME) AS order_purchase_timestamp,
	CAST(order_approved_at AS DATETIME) AS order_approved_at
	FROM stg.orders
	WHERE order_id IS NOT NULL AND customer_id IS NOT NULL  

	-- Drop the view if it already exists (to avoid errors when re-running)
IF OBJECT_ID ( 'VW_Payment_clean', 'V') IS NOT NULL
	DROP VIEW VW_Payment_clean

-- Create the clean view
CREATE VIEW VW_Payment_clean AS 
Select 
	ROW_NUMBER() OVER (ORDER BY Order_id) AS order_key,
	Order_id,
	UPPER(payment_sequential) AS payment_sequential,
	UPPER(payment_type) AS payment_type,
	UPPER(payment_installments) AS payment_installments,
	payment_value
	FROM stg.payments
	WHERE Order_id IS NOT NULL

		-- Drop the view if it already exists (to avoid errors when re-running)
IF OBJECT_ID ( 'VW_Products_clean', 'V') IS NOT NULL
	DROP VIEW VW_Products_clean

-- Create the clean view
CREATE VIEW VW_Products_clean AS 
Select 
	ROW_NUMBER() OVER (ORDER BY product_id) AS product_key,
	product_id,
	UPPER(TRIM( product_category_name )) AS product_category_name,
	product_weight_g,
	product_length_cm,
	product_height_cm,
	product_width_cm
	FROM stg.products
	WHERE product_id IS NOT NULL 

	

/*===================================================================================================
                    BUSINESS QUESTION 
-- 1. Monthly Sales Trends 
-- Q: what is the monthnly sales revenue trends?
==================================================================================================*/
SELECT 
	MONTH(o.order_purchase_timestamp) AS Month,
	YEAR(o.order_purchase_timestamp) AS Year,
	SUM(oi.price + oi.shipping_charges ) AS total_sales
FROM VW_Orders_clean AS o
INNER JOIN VW_Orderitems_clean AS oi
ON o.order_key = oi.order_key
GROUP BY MONTH(o.order_purchase_timestamp),YEAR(o.order_purchase_timestamp)
ORDER BY Month


/*===================================================================================================
                    BUSINESS QUESTION 
-- 2. TOP 5 Product Categories
-- Q: Which product categories generates the most sales?
==================================================================================================*/
SELECT 
	TOP 5
	P.Product_category_name,
    SUM(oi.price) AS total_sales
FROM VW_Products_clean AS p
INNER JOIN VW_Orderitems_clean AS oi
ON p.product_key = oi.product_key
GROUP BY Product_category_name
ORDER BY total_sales DESC


/*===================================================================================================
                    BUSINESS QUESTION 
-- 3. Payment Method 
-- Q: what payment methods do customers perefer?
==================================================================================================*/
SELECT 
	payment_type,
	COUNT(*) AS total_transaction
FROM VW_Payment_clean 
GROUP BY payment_type
ORDER BY total_transaction DESC


/*===================================================================================================
                    BUSINESS QUESTION 
-- 4. Customer Rentention 
-- Q: How many repeat vs. one-time customers do we have?
==================================================================================================*/
SELECT 
	CASE WHEN order_count > 1 THEN 'Repeat customer' 
	ELSE 'One-time customer'
	END AS Customer_type,
	COUNT(*) AS customer_count
FROM (
SELECT 
	c.customer_KEY,
	COUNT(o.order_key) AS order_count
	FROM VW_Customers_clean AS c
	INNER JOIN VW_Orders_clean AS o 
	ON c.customer_key = o.customer_key
	GROUP BY c.Customer_key
	) t
	GROUP BY
		CASE
		WHEN order_count > 1 THEN 'Repeat customer' 
	ELSE 'One-time customer'
	END 

	/*===================================================================================================
                    BUSINESS QUESTION 
-- 5. Average Order Value 
-- Q: On average, how much do customers spend per order?
==================================================================================================*/

SELECT
	AVG(order_value) AS avg_order_value
	FROM (
SELECT
	o.order_key,
	SUM(oi.price + oi.shipping_charges ) AS order_value
	FROM VW_Orders_clean AS o
	LEFT JOIN VW_Orderitems_clean AS oi
	ON o.order_key = oi.order_key
	GROUP BY o.order_key
	) t

/*===================================================================================================
                    BUSINESS QUESTION 
-- 6. Top cities by sales  
-- Q: which customer cities generate the most sales?
==================================================================================================*/
SELECT
	c.Customer_city,
	SUM(oi.price + oi.shipping_charges ) AS total_sales
FROM VW_Orders_clean AS o
LEFT JOIN VW_Customers_clean AS c
ON o.Customer_key = c.Customer_key
LEFT JOIN VW_Orderitems_clean AS oi
ON o.order_key = oi.order_key
GROUP BY c.Customer_city
ORDER BY  total_sales DESC


/*===================================================================================================
                    BUSINESS QUESTION 
-- 7. Revenue contributio by TOP 5 categories 
-- Q: which categories contribute most to revenue?
==================================================================================================*/
SELECT 
	TOP 5
	p.product_category_name,
	SUM(oi.price) AS total_sales
FROM VW_Products_clean AS p
LEFT JOIN VW_Orderitems_clean oi
ON p.product_key = oi.product_key
GROUP BY p.product_category_name 
ORDER BY total_sales DESC
