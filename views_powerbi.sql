CREATE OR REPLACE VIEW vw_sales_enriched AS

CREATE OR REPLACE VIEW vw_daily_metrics AS
SELECT
    date,
    SUM(total_amt) AS daily_revenue,
    COUNT(bill_no) AS daily_transactions
FROM sales_clean
GROUP BY date;


CREATE OR REPLACE VIEW vw_daily_weekday_weekend AS
SELECT
    date,
    CASE WHEN EXTRACT(DOW FROM date) IN (0,6) THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    SUM(total_amt) AS daily_revenue,
    COUNT(DISTINCT bill_no) AS daily_transactions
FROM sales
GROUP BY 1,2
ORDER BY 1;
