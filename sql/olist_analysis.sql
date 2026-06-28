USE project1;
SELECT COUNT(*) FROM final_orders_info;
SELECT * FROM final_orders_info;

#GMV
SELECT order_id, COUNT(*) FROM final_orders_info 
GROUP BY order_id HAVING COUNT(*) > 1 LIMIT 5;#同一订单出现多次，但是payment_value一样。
SELECT payment_value FROM final_orders_info WHERE order_id = 'e6ce16cb79ec1d90b1da9085a6118aeb';#验证

SELECT SUM(payment_value) 
FROM 
(SELECT DISTINCT order_id,payment_value FROM final_orders_info) gmv;#GMV结果
#订单数order_count
SELECT COUNT(DISTINCT order_id) FROM final_orders_info order_count;
#用户数customer_id
SELECT COUNT(DISTINCT customer_id) FROM final_orders_info customer_count;
#客单价 avg_order = GMV /订单数
SELECT
(SELECT SUM(payment_value) 
FROM 
(SELECT DISTINCT order_id,payment_value FROM final_orders_info) gmv) 
/ (SELECT COUNT(DISTINCT order_id) FROM final_orders_info order_count) avg_order_value;

#合为一张新表gmv+订单数+用户数+客单价
SELECT
(SELECT SUM(payment_value) FROM (SELECT DISTINCT order_id,payment_value FROM final_orders_info) gmv1) AS GMV,
(SELECT COUNT(DISTINCT order_id) FROM final_orders_info) AS order_count,
(SELECT COUNT(DISTINCT customer_id) FROM final_orders_info) AS customer_count,
((SELECT SUM(payment_value) FROM (SELECT DISTINCT order_id,payment_value FROM final_orders_info) gmv2) 
/ (SELECT COUNT(DISTINCT order_id) FROM final_orders_info order_count2)) AS avg_order_value;

CREATE TABLE IF NOT EXISTS dim_overview AS
WITH distinct_order AS (SELECT DISTINCT order_id,payment_value,customer_id 
						FROM final_orders_info WHERE payment_value IS NOT NULL)
SELECT SUM(payment_value) AS gmv,
COUNT(DISTINCT order_id) AS order_count,
COUNT(DISTINCT customer_id) AS customer_count,
SUM(payment_value) / COUNT(DISTINCT order_id) AS avg_order_value
FROM distinct_order;# ------------------------------------------------总览


##趋势分析
#月销售趋势
CREATE TABLE dim_monthly_trend AS 
WITH t AS (
			SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
			FROM final_orders_info
		   )#去重
SELECT 
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    SUM(payment_value) AS monthly_gmv,
    COUNT(DISTINCT order_id) AS monthly_order_count,
    COUNT(DISTINCT customer_id) AS monthly_customer
FROM t
WHERE payment_value IS NOT NULL
GROUP BY order_month
ORDER BY order_month;#----------------------------------------------月度趋势


##价值分析，RFM模型，谁是高价值用户
SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
FROM final_orders_info;#去重

SELECT MAX(order_purchase_timestamp) FROM final_orders_info;#全局截止日期

SELECT customer_id,DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM final_orders_info),
							 MAX(order_purchase_timestamp)) recency_date
FROM final_orders_info GROUP BY customer_id;#用户最近下单的差值（天数）

SELECT customer_id,COUNT(DISTINCT order_id),SUM(payment_value) FROM 
(
SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
FROM final_orders_info
) distinct_order GROUP BY customer_id;#用户周期内下单次数和消费金额

WITH distinct_order AS
(SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
FROM final_orders_info)
SELECT customer_id,
DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM final_orders_info),MAX(order_purchase_timestamp)) AS recency_days,
COUNT(DISTINCT order_id) AS frequency,
SUM(payment_value) AS sum_payment
FROM distinct_order
GROUP BY customer_id;#CTE写法，rfm

#RFM打分
WITH distinct_order AS
(SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
FROM final_orders_info),
rfm_order AS (SELECT customer_id,
DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM final_orders_info),MAX(order_purchase_timestamp)) AS recency_days,
COUNT(DISTINCT order_id) AS frequency,
SUM(payment_value) AS sum_payment
FROM distinct_order
GROUP BY customer_id),
rfm_scored AS (SELECT customer_id,recency_days,frequency,sum_payment,
6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,#越近分越高
NTILE(5) OVER (ORDER BY sum_payment ASC) AS m_score FROM rfm_order )#价值越高分越大
SELECT *,CASE WHEN r_score >= 4 AND m_score >= 4 THEN '高价值用户'
			  WHEN r_score >= 3 OR m_score >= 3  THEN '一般价值用户'
			  ELSE '低价值用户' END AS user_segment
FROM rfm_scored
WHERE sum_payment IS NOT NULL;

#用户分层
CREATE TABLE dim_rfm_segment 
WITH distinct_order AS
(SELECT DISTINCT order_id, order_purchase_timestamp, payment_value, customer_id
FROM final_orders_info),
rfm_order AS (SELECT customer_id,
DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM final_orders_info),MAX(order_purchase_timestamp)) AS recency_days,
COUNT(DISTINCT order_id) AS frequency,
SUM(payment_value) AS sum_payment
FROM distinct_order
GROUP BY customer_id),
rfm_scored AS (SELECT customer_id,recency_days,frequency,sum_payment,
6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,#越近分越高
NTILE(5) OVER (ORDER BY sum_payment ASC) AS m_score FROM rfm_order  WHERE sum_payment IS NOT NULL)#价值越高分越大
SELECT CASE WHEN r_score >= 4 AND m_score >= 4 THEN '高价值用户'
			  WHEN r_score >= 3 OR m_score >= 3  THEN '一般价值用户'
			  ELSE '低价值用户' END AS user_segment,
COUNT(*) AS user_count,
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct,
ROUND(AVG(recency_days), 0) AS avg_recency,
ROUND(AVG(sum_payment), 2) AS avg_payment
FROM rfm_scored
GROUP BY user_segment
ORDER BY user_count DESC;#-----------------------------------------------用户分层

#商品分析
SELECT product_category_name,
COUNT(DISTINCT order_id) AS order_count,
ROUND(SUM(payment_value),2) AS total_revenue,
ROUND(AVG(review_score),2) AS avg_score
FROM final_orders_info
WHERE product_category_name IS NOT NULL
GROUP BY product_category_name
ORDER BY total_revenue DESC
LIMIT 10;

WITH order_analyze AS ( SELECT product_category_name,
						COUNT(DISTINCT order_id) AS order_count,
						ROUND(SUM(payment_value),2) AS total_revenue,
						ROUND(AVG(review_score),2) AS avg_score
						FROM final_orders_info
						WHERE product_category_name IS NOT NULL
						GROUP BY product_category_name)
SELECT product_category_name,order_count,total_revenue,avg_score,
RANK() OVER(ORDER BY total_revenue DESC) AS revenue_rank,
ROUND(total_revenue / SUM(total_revenue) OVER() * 100,2) AS revenue_ratio
FROM order_analyze
ORDER BY total_revenue DESC
LIMIT 20;#占比及评分

WITH order_analyze AS ( SELECT product_category_name,
						COUNT(DISTINCT order_id) AS order_count,
						ROUND(SUM(payment_value),2) AS total_revenue,
						ROUND(AVG(review_score),2) AS avg_score
						FROM final_orders_info
						WHERE product_category_name IS NOT NULL
						GROUP BY product_category_name),
t AS (SELECT product_category_name,order_count,total_revenue,avg_score,
RANK() OVER(ORDER BY total_revenue DESC) AS revenue_rank,
ROUND(total_revenue / SUM(total_revenue) OVER() * 100,2) AS revenue_ratio
FROM order_analyze
ORDER BY total_revenue DESC)
SELECT *
FROM t
WHERE revenue_rank <= 10        -- 销售额前10
  AND avg_score < 4.0           -- 但评分低于4分
ORDER BY total_revenue DESC;#高销售低评分商品


WITH order_analyze AS ( SELECT product_category_name,
						COUNT(DISTINCT order_id) AS order_count,
						ROUND(SUM(payment_value),2) AS total_revenue,
						ROUND(AVG(review_score),2) AS avg_score
						FROM final_orders_info
						WHERE product_category_name IS NOT NULL
						GROUP BY product_category_name),
t AS (SELECT product_category_name,order_count,total_revenue,avg_score,
RANK() OVER(ORDER BY total_revenue DESC) AS revenue_rank,
ROUND(total_revenue / SUM(total_revenue) OVER() * 100,2) AS revenue_ratio
FROM order_analyze
ORDER BY total_revenue DESC)
SELECT *
FROM t
WHERE revenue_rank >= 10        -- 销售额非10
  AND avg_score > 4.0           -- 但评分低于大于分
ORDER BY total_revenue DESC;#高评分，低销售

#二八法则
CREATE TABLE dim_product_analysis AS
WITH order_analyze AS ( SELECT product_category_name,
						COUNT(DISTINCT order_id) AS order_count,
						ROUND(SUM(payment_value),2) AS total_revenue,
						ROUND(AVG(review_score),2) AS avg_score
						FROM final_orders_info
						WHERE product_category_name IS NOT NULL
						GROUP BY product_category_name),
t AS (SELECT product_category_name,order_count,total_revenue,avg_score,
RANK() OVER(ORDER BY total_revenue DESC) AS revenue_rank,
ROUND(total_revenue / SUM(total_revenue) OVER() * 100,4) AS revenue_ratio,
PERCENT_RANK() OVER(ORDER BY total_revenue DESC) as pct#百分位占比
FROM order_analyze),
cumulative_pct AS (
SELECT *,
ROUND(SUM(revenue_ratio) OVER(ORDER BY total_revenue DESC), 4) AS cum_pct#按营收从高到低累加占比
FROM t
)
SELECT *
FROM cumulative_pct
WHERE cum_pct <= 80   #只看贡献了前80%营收的品类
ORDER BY total_revenue DESC;#-------------------------------------------------二八法则


##地域GMV分析
SELECT COUNT(DISTINCT order_id) AS order_count,
COUNT(DISTINCT customer_id) AS customer_count,
customer_state,customer_city,
ROUND(SUM(payment_value),2 )AS gmv,
ROUND(AVG(payment_value),2) AS avg_order_gmv
FROM final_orders_info
WHERE payment_value IS NOT NULL
GROUP BY customer_state,customer_city
ORDER BY gmv DESC;

SELECT
customer_state,
ROUND(SUM(payment_value)/COUNT(DISTINCT order_id),2) AS aov
FROM final_orders_info
GROUP BY customer_state
ORDER BY aov DESC;#地域客单价

SELECT  customer_state,
AVG(DATEDIFF(order_delivered_customer_date,order_purchase_timestamp)) AS delivered_days,
AVG(review_score) AS avg_score
FROM final_orders_info
GROUP BY customer_state
ORDER BY delivered_days ASC,avg_score DESC;#物流及评分分析

WITH distinct_order AS 
(SELECT DISTINCT order_id, order_delivered_customer_date, order_estimated_delivery_date, review_score,customer_state
FROM final_orders_info)
SELECT  customer_state,
COUNT(DISTINCT order_id) AS order_count,
SUM(CASE WHEN order_delivered_customer_date < order_estimated_delivery_date THEN 1 ELSE 0 END) AS on_time_orders,
ROUND(SUM(CASE WHEN order_delivered_customer_date < order_estimated_delivery_date THEN 1 ELSE 0 END) 
/ 
COUNT(DISTINCT order_id) * 100,2) AS ontime_pct,
AVG(review_score) AS avg_score
FROM distinct_order
GROUP BY customer_state
ORDER BY ontime_pct DESC,avg_score DESC;#各地区的准时率和评分关系


SELECT COUNT(DISTINCT order_id) AS order_count,
COUNT(DISTINCT customer_id) AS customer_count,
customer_state,customer_city,
ROUND(SUM(payment_value),2) AS gmv,
AVG(review_score) AS avg_score
FROM final_orders_info
WHERE payment_value IS NOT NULL
GROUP BY customer_state,customer_city
ORDER BY gmv DESC;#gmv与评分分析

SELECT COUNT(DISTINCT order_id) AS order_count,
COUNT(DISTINCT customer_id) AS customer_count,
customer_state,customer_city,
ROUND(SUM(payment_value),2) AS gmv,
AVG(review_score) AS avg_score
FROM final_orders_info
WHERE payment_value IS NOT NULL
GROUP BY customer_state,customer_city
HAVING avg_score < 4
ORDER BY gmv DESC;#问题地区，挣钱但评分差

CREATE TABLE dim_area_analysis AS
WITH distinct_order AS (
  SELECT DISTINCT order_id, order_delivered_customer_date,
    order_estimated_delivery_date, order_purchase_timestamp,
    payment_value, review_score, customer_state, customer_city
  FROM final_orders_info
)
SELECT 
  customer_state,
  COUNT(DISTINCT order_id) AS order_count,
  ROUND(SUM(payment_value), 2) AS gmv,
  ROUND(SUM(payment_value) / COUNT(DISTINCT order_id), 2) AS aov,
  ROUND(AVG(DATEDIFF(order_delivered_customer_date,
                     order_purchase_timestamp)), 1) AS avg_delivery_days,
  ROUND(SUM(CASE WHEN order_delivered_customer_date < order_estimated_delivery_date 
                 THEN 1 ELSE 0 END) 
        / COUNT(DISTINCT order_id) * 100, 2) AS ontime_pct,
  ROUND(AVG(review_score), 2) AS avg_score
FROM distinct_order
WHERE payment_value IS NOT NULL
GROUP BY customer_state
ORDER BY gmv DESC;#----------------------------------------------------------地域物流综合分析

