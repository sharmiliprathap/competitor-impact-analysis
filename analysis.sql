DROP TABLE IF EXISTS sales;

CREATE TABLE sales (
    date DATE NOT NULL,
    transaction_id INT PRIMARY KEY,
    bill_no INT NOT NULL,
    sales_type VARCHAR(50),
    gross_amt DECIMAL(10,2),
    gst_amt DECIMAL(10,2),
    total_amt DECIMAL(10,2)
);

COPY sales
FROM  '/private/tmp/cleaned_sales_report_2024-2025.csv'
DELIMITER ',' CSV HEADER;


--DESCRIPTIVE ANALYSIS


--Looking at the Average, Minimum and Maximum values for the two years

SELECT AVG(total_amt) avg_transaction_value,
       MIN(total_amt) min_transaction_value,
       MAX(total_amt) max_transaction_value
FROM sales s;


--Analyzing trends in sales over time (monthly)

SELECT DATE_TRUNC('month', date) AS month,
       SUM(total_amt) as total_amt_monthly,
       COUNT(*) AS transaction_count
FROM sales
GROUP BY 1
ORDER BY 1;


-- Looking at daily sales and average bill value

SELECT date,
       SUM(total_amt) AS daily_total_sales,
       COUNT(*) AS daily_transaction_count,
       AVG(total_amt) AS avg_bill_value
FROM sales
GROUP BY 1
ORDER BY 1;


-- Creating period view for analysis across 3 time periods

CREATE OR REPLACE VIEW vw_period AS
SELECT DISTINCT
    date,
    CASE
        WHEN date < DATE '2025-04-01' THEN 'Pre-Closure'
        WHEN date BETWEEN DATE '2025-04-01' AND DATE '2025-07-31' THEN 'Post-Closure'
        ELSE 'Post-Opening'
    END AS period_name,
    CASE
        WHEN date < DATE '2025-04-01' THEN 1
        WHEN date BETWEEN DATE '2025-04-01' AND DATE '2025-07-31' THEN 2
        ELSE 3
    END AS period_order
FROM sales
GROUP BY date
ORDER BY date;


--Did average daily sales change across the 3 event periods?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name AS period,
        p.period_order,
        SUM(s.total_amt) AS daily_sales,
        COUNT(*) AS daily_transaction_count
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,3
)

SELECT period,
       AVG(daily_sales) AS avg_daily_sales,
       AVG(daily_transaction_count) AS avg_daily_transactions
FROM daily_sales
GROUP BY period, period_order
ORDER BY period_order;


-- Did average monthly sales change across the 3 event periods?

WITH monthly_sales AS (
    SELECT DATE_TRUNC('month', s.date) AS month,
           p.period_name AS period,
           p.period_order, 
           SUM(s.total_amt) AS monthly_sales,
           COUNT(*) AS monthly_transaction_count
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,3
)

SELECT period,
       AVG(monthly_sales) AS avg_monthly_sales,
       AVG(monthly_transaction_count) AS avg_monthly_transactions
FROM monthly_sales
GROUP BY 1, period_order
ORDER BY period_order;


-- Was the uplift consistent between post-closure and opening or did the sales dip post-opening?

    DATE_TRUNC('month', s.date) AS month,
    SUM(s.total_amt) AS monthly_sales,
    p.period_name AS period
FROM sales s
JOIN vw_period p 
ON s.date = p.date
WHERE period_name IN ('Post-Closure', 'Post-Opening')
GROUP BY 1,3
ORDER BY 1;


-- DIAGNOSTIC ANALYSIS

-- Was growth attributable to higher footfall or higher average basket size?

WITH daily_metrics AS (
    SELECT
        date,
        COUNT(*) AS daily_transactions,
        AVG(total_amt) AS daily_avg_bill
    FROM sales
    GROUP BY date
),
labeled AS (
    SELECT
        d.*,
        p.period_name,
        p.period_order
    FROM daily_metrics d
    JOIN vw_period p ON d.date = p.date
)

SELECT
    period_name,
    AVG(daily_transactions) AS avg_daily_transactions,
    AVG(daily_avg_bill) AS avg_bill_value
FROM labeled
GROUP BY period_name, period_order
ORDER BY period_order;


-- Was growth attributable to higher weekend sales or weekday sales?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name,
        COUNT(DISTINCT s.bill_no) AS bills_per_day,
        SUM(s.total_amt) AS sales_per_day,
        AVG(s.total_amt) AS avg_bill_value,
        CASE WHEN EXTRACT(DOW FROM s.date) IN (0, 6) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        p.period_order
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,6,7
)

SELECT
    period_name,
    day_type,
    AVG(bills_per_day) AS avg_daily_transactions,
    AVG(sales_per_day) AS avg_daily_sales,
    AVG(avg_bill_value) AS avg_bill_value
FROM daily_sales
GROUP BY period_name, period_order, day_type
ORDER BY period_order, day_type;


-- Is the revenue uplift consistent or driven by outliers?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name,
        SUM(s.total_amt) AS sales_per_day,
        AVG(s.total_amt) AS avg_bill_value,
        CASE WHEN EXTRACT(DOW FROM s.date) IN (0, 6) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        p.period_order
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,5,6
)

SELECT period_name,
       AVG(sales_per_day) mean_daily_sales,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sales_per_day) AS median_daily_sales,
       STDDEV(sales_per_day) AS stddev_daily_sales,
       MIN(sales_per_day) AS min_daily_sales,
       MAX(sales_per_day) AS max_daily_sales
FROM daily_sales
GROUP BY 1, period_order
ORDER BY period_order
;

-- How did weekly sales evolve immediately after the closure?

WITH daily_sales_post_closure AS (
    SELECT
        s.date,
        SUM(total_amt) AS sales_per_day
    FROM sales s 
    JOIN vw_period p 
    ON s.date = p.date
    WHERE period_name = 'Post-Closure'
    GROUP BY 1
)
SELECT
    FLOOR((date - DATE '2025-03-31') / 7) + 1 AS week_number,
    AVG(sales_per_day) AS avg_daily_sales,
    SUM(sales_per_day) AS total_weekly_sales
FROM daily_sales_post_closure
GROUP BY week_number
ORDER BY week_number;


-- Did the payment mix shift across the three periods?

WITH t1 AS (
    SELECT
        p.period_name,
        p.period_order,
        SUM(CASE WHEN s.sales_type = 'CASH' THEN 1 ELSE 0 END) AS cash_count,
        SUM(CASE WHEN s.sales_type = 'CARD' THEN 1 ELSE 0 END) AS card_count,
        SUM(CASE WHEN s.sales_type = 'SPLIT' THEN 1 ELSE 0 END) AS split_count,
        COUNT(*) AS total_count
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2
)

SELECT 
    period_name,
    ROUND(100.0 * cash_count / total_count, 2) AS cash_pct,
    ROUND(100.0 * card_count / total_count, 2) AS card_pct,
    ROUND(100.0 * split_count / total_count, 2) AS split_pct
FROM t1
ORDER BY period_order;

-- CAUSAL ANALYSIS

-- Is the revenue uplift consistent or driven by outliers?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name,
        p.period_order,
        SUM(s.total_amt) AS sales_per_day,
        AVG(s.total_amt) AS avg_bill_value
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,3
)

SELECT period_name,
       AVG(sales_per_day) mean_daily_sales,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sales_per_day) AS median_daily_sales,
       MIN(sales_per_day) AS min_daily_sales,
       MAX(sales_per_day) AS max_daily_sales
FROM daily_sales
GROUP BY 1, period_order
ORDER BY period_order
;


-- Did sales volatility change across the periods?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name,
        p.period_order,
        SUM(s.total_amt) AS sales_per_day
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,3
)

SELECT period_name,
       AVG(sales_per_day) mean_daily_sales,
       STDDEV(sales_per_day) AS stddev_daily_sales
FROM daily_sales
GROUP BY 1, period_order
ORDER BY period_order
;


-- LAG EFFECT: -- How quickly did sales react after the competitor closed?

WITH daily_sales AS (
    SELECT
        date,
        SUM(total_amt) AS daily_sales
    FROM sales
    GROUP BY date
),

baseline AS (
    SELECT
        AVG(daily_sales) AS baseline_avg
    FROM daily_sales
    WHERE date >= DATE '2025-01-01'
      AND date < DATE '2025-04-01'
),

post_event AS (
    SELECT
        d.date,
        d.daily_sales,
        b.baseline_avg,
        d.daily_sales - b.baseline_avg AS uplift_amount,
        CASE WHEN d.daily_sales > b.baseline_avg THEN 1 ELSE 0 END AS above_baseline_flag
    FROM daily_sales d
    CROSS JOIN baseline b
    WHERE d.date >= DATE '2025-04-01'
      AND d.date < DATE '2025-05-31'
)

SELECT
    p.period_name,
    pe.date,
    pe.daily_sales,
    pe.baseline_avg,
    pe.uplift_amount,
    pe.above_baseline_flag
FROM post_event pe
JOIN vw_period p ON pe.date = p.date
ORDER BY pe.date;


--- How much of the captured revenue was lost after the new competitor opened?

WITH daily_sales AS (
    SELECT
        s.date,
        p.period_name,
        p.period_order,
        SUM(s.total_amt) AS daily_sales
    FROM sales s
    JOIN vw_period p ON s.date = p.date
    GROUP BY 1,2,3
),

period_avg AS (
    SELECT
        period_name,
        period_order,
        AVG(daily_sales) AS avg_daily_sales
    FROM daily_sales
    GROUP BY 1,2
),

pivot AS (
    SELECT
        MAX(CASE WHEN period_name = 'Pre-Closure' THEN avg_daily_sales END) AS pre_closure_avg,
        MAX(CASE WHEN period_name = 'Post-Closure' THEN avg_daily_sales END) AS post_closure_avg,
        MAX(CASE WHEN period_name = 'Post-Opening' THEN avg_daily_sales END) AS post_opening_avg
    FROM period_avg
)

SELECT
    ROUND(pre_closure_avg, 2) AS pre_closure_avg_daily_sales,
    ROUND(post_closure_avg, 2) AS post_closure_avg_daily_sales,
    ROUND(post_opening_avg, 2) AS post_opening_avg_daily_sales,

    ROUND((post_closure_avg - pre_closure_avg), 2) AS uplift_captured_post_closure_avg,
    ROUND((post_closure_avg - post_opening_avg), 2) AS uplift_lost_post_opening_avg,

    ROUND(
        ((post_opening_avg - pre_closure_avg) / NULLIF((post_closure_avg - pre_closure_avg), 0)) * 100.0
    , 2) AS retention_percent_post_opening_avg
FROM pivot;