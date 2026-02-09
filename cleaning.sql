-- 1) Create raw staging table matching the raw CSV headers
DROP TABLE IF EXISTS sales_raw;

CREATE TABLE sales_raw (
    "Date" TEXT,
    "Bill No" INT,
    "CustomerName" TEXT,
    "SalesType" TEXT,
    "GrossAmt" NUMERIC,
    "GST Amt" NUMERIC,
    "TotAmt" NUMERIC
);

-- 2) Load raw CSV (adjust path as needed)
COPY sales_raw
FROM '/private/tmp/2024-2025 report consolidated_new.csv'
DELIMITER ',' CSV HEADER;

-- 3) Create cleaned table with:
--    - Date parsed
--    - CustomerName dropped
--    - Columns renamed
--    - transaction_id created

DROP TABLE IF EXISTS sales;

CREATE TABLE sales AS
SELECT
    TO_DATE("Date", 'DD-MM-YYYY') AS date,
    ROW_NUMBER() OVER (ORDER BY TO_DATE("Date", 'DD-MM-YYYY'), "Bill No") AS transaction_id,
    "Bill No" AS bill_no,
    "SalesType" AS sales_type,
    "GrossAmt" AS gross_amt,
    "GST Amt" AS gst_amt,
    "TotAmt" AS total_amt
FROM sales_raw;

-- 4) Check for nulls
SELECT
    COUNT(*) FILTER (WHERE date IS NULL) AS date_nulls,
    COUNT(*) FILTER (WHERE bill_no IS NULL) AS bill_no_nulls,
    COUNT(*) FILTER (WHERE sales_type IS NULL) AS sales_type_nulls,
    COUNT(*) FILTER (WHERE gross_amt IS NULL) AS gross_amt_nulls,
    COUNT(*) FILTER (WHERE gst_amt IS NULL) AS gst_amt_nulls,
    COUNT(*) FILTER (WHERE total_amt IS NULL) AS total_amt_nulls
FROM sales;

-- 5) Check duplicate transaction_ids (should be 0)
SELECT transaction_id, COUNT(*)
FROM sales
GROUP BY 1
HAVING COUNT(*) > 1;

-- 6) Check duplicates per day + bill_no (should be 0 if bill_no is unique per day)
SELECT date, bill_no, COUNT(*)
FROM sales
GROUP BY 1,2
HAVING COUNT(*) > 1;

-- 7) Check for negative or zero amounts
SELECT COUNT(*) AS zero_or_negative
FROM sales
WHERE total_amt <= 0 OR gross_amt < 0 OR gst_amt < 0;

-- 8) Date range check
SELECT MIN(date) AS min_date, MAX(date) AS max_date
FROM sales;

-- 9) Export cleaned dataset
COPY sales TO '/private/tmp/cleaned_sales_report_2024-2025.csv' CSV HEADER;
