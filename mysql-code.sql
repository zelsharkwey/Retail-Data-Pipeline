-- ============================================================================
-- DATABASE CREATION
-- ============================================================================
CREATE DATABASE IF NOT EXISTS retail_dwh;
USE retail_dwh;

-- ============================================================================
-- STAGING LAYER (Tables for raw CSV ingestion)
-- ============================================================================
-- We use VARCHAR for everything in staging to prevent load failures on dirty data.

DROP TABLE IF EXISTS stg_DimCustomer;
CREATE TABLE stg_DimCustomer (
    Customer_Key VARCHAR(255),
    Customer_Name VARCHAR(255),
    Customer_Category VARCHAR(255)
);

DROP TABLE IF EXISTS stg_DimDate;
CREATE TABLE stg_DimDate (
    Date_Key VARCHAR(255),
    Full_Date VARCHAR(255),
    Day VARCHAR(50),
    Month VARCHAR(50),
    Month_Name VARCHAR(50),
    Quarter VARCHAR(50),
    Year VARCHAR(50),
    Season VARCHAR(50)
);

DROP TABLE IF EXISTS stg_DimProduct;
CREATE TABLE stg_DimProduct (
    Product_Key VARCHAR(255),
    Product_Name VARCHAR(500)
);

DROP TABLE IF EXISTS stg_DimPromotion;
CREATE TABLE stg_DimPromotion (
    Promotion_Key VARCHAR(255),
    Promotion VARCHAR(255),
    Discount_Applied VARCHAR(50)
);

DROP TABLE IF EXISTS stg_DimStore;
CREATE TABLE stg_DimStore (
    Store_Key VARCHAR(255),
    City VARCHAR(255),
    Store_Type VARCHAR(255)
);

DROP TABLE IF EXISTS stg_FactProductBridge;
CREATE TABLE stg_FactProductBridge (
    Transaction_ID VARCHAR(255),
    Product_Key VARCHAR(255)
);

DROP TABLE IF EXISTS stg_FactSales;
CREATE TABLE stg_FactSales (
    Transaction_ID VARCHAR(255),
    Date_Key VARCHAR(255),
    Customer_Key VARCHAR(255),
    Store_Key VARCHAR(255),
    Promotion_Key VARCHAR(255),
    Total_Items VARCHAR(255),
    Total_Cost VARCHAR(255)
);

-- ============================================================================
-- CSV LOADING
-- ============================================================================
-- INSTRUCTIONS: Replace '/REPLACE_WITH_YOUR_PATH/' with your actual local or server path.
-- Ensure MySQL secure_file_priv allows loading from this directory.

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/dim_customer.csv'
INTO TABLE stg_DimCustomer
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/dim_date.csv'
INTO TABLE stg_DimDate
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/dim_product.csv'
INTO TABLE stg_DimProduct
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/dim_promotion.csv'
INTO TABLE stg_DimPromotion
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/dim_store.csv'
INTO TABLE stg_DimStore
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/fact_product_bridge.csv'
INTO TABLE stg_FactProductBridge
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA INFILE '/REPLACE_WITH_YOUR_PATH/fact_sales.csv'
INTO TABLE stg_FactSales
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- ============================================================================
-- WAREHOUSE TABLES (Star Schema with Constraints & Indexes)
-- ============================================================================

DROP TABLE IF EXISTS FactProductBridge;
DROP TABLE IF EXISTS FactSales;
DROP TABLE IF EXISTS DimCustomer;
DROP TABLE IF EXISTS DimDate;
DROP TABLE IF EXISTS DimProduct;
DROP TABLE IF EXISTS DimPromotion;
DROP TABLE IF EXISTS DimStore;

CREATE TABLE DimCustomer (
    Customer_Key INT PRIMARY KEY,
    Customer_Name VARCHAR(255),
    Customer_Category VARCHAR(100)
);

CREATE TABLE DimDate (
    Date_Key INT PRIMARY KEY,
    Full_Date DATE,
    Day INT,
    Month INT,
    Month_Name VARCHAR(50),
    Quarter INT,
    Year INT,
    Season VARCHAR(50)
);

CREATE TABLE DimProduct (
    Product_Key INT PRIMARY KEY,
    Product_Name VARCHAR(255)
);

CREATE TABLE DimPromotion (
    Promotion_Key INT PRIMARY KEY,
    Promotion VARCHAR(255),
    Discount_Applied BOOLEAN
);

CREATE TABLE DimStore (
    Store_Key INT PRIMARY KEY,
    City VARCHAR(100),
    Store_Type VARCHAR(100)
);

CREATE TABLE FactSales (
    Transaction_ID BIGINT PRIMARY KEY,
    Date_Key INT,
    Customer_Key INT,
    Store_Key INT,
    Promotion_Key INT,
    Total_Items INT,
    Total_Cost DECIMAL(10, 2),
    FOREIGN KEY (Date_Key) REFERENCES DimDate(Date_Key),
    FOREIGN KEY (Customer_Key) REFERENCES DimCustomer(Customer_Key),
    FOREIGN KEY (Store_Key) REFERENCES DimStore(Store_Key),
    FOREIGN KEY (Promotion_Key) REFERENCES DimPromotion(Promotion_Key)
);

CREATE TABLE FactProductBridge (
    Transaction_ID BIGINT,
    Product_Key INT,
    PRIMARY KEY (Transaction_ID, Product_Key),
    FOREIGN KEY (Transaction_ID) REFERENCES FactSales(Transaction_ID),
    FOREIGN KEY (Product_Key) REFERENCES DimProduct(Product_Key)
);

-- Analytics-friendly Optimization (Indexes)
CREATE INDEX idx_fact_date ON FactSales(Date_Key);
CREATE INDEX idx_fact_cust ON FactSales(Customer_Key);
CREATE INDEX idx_fact_store ON FactSales(Store_Key);
CREATE INDEX idx_fact_promo ON FactSales(Promotion_Key);
CREATE INDEX idx_bridge_prod ON FactProductBridge(Product_Key);

-- ============================================================================
-- DATA CLEANING & LOADING (ETL from Staging to DWH)
-- ============================================================================

-- 1. Load DimCustomer
INSERT IGNORE INTO DimCustomer (Customer_Key, Customer_Name, Customer_Category)
SELECT 
    CAST(TRIM(Customer_Key) AS UNSIGNED),
    TRIM(Customer_Name),
    TRIM(Customer_Category)
FROM stg_DimCustomer
WHERE Customer_Key IS NOT NULL AND TRIM(Customer_Key) != '';

-- 2. Load DimDate (Convert timestamp to Date Grain, group by Date to avoid dupes)
-- Using YYYYMMDD integer format for Date_Key
INSERT IGNORE INTO DimDate (Date_Key, Full_Date, Day, Month, Month_Name, Quarter, Year, Season)
SELECT 
    CAST(DATE_FORMAT(CAST(LEFT(Full_Date, 10) AS DATE), '%Y%m%d') AS UNSIGNED) AS Date_Key,
    CAST(LEFT(Full_Date, 10) AS DATE) AS Full_Date,
    MAX(CAST(TRIM(Day) AS UNSIGNED)),
    MAX(CAST(TRIM(Month) AS UNSIGNED)),
    MAX(TRIM(Month_Name)),
    MAX(CAST(TRIM(Quarter) AS UNSIGNED)),
    MAX(CAST(TRIM(Year) AS UNSIGNED)),
    MAX(TRIM(Season))
FROM stg_DimDate
WHERE Full_Date IS NOT NULL AND TRIM(Full_Date) != ''
GROUP BY CAST(LEFT(Full_Date, 10) AS DATE);

-- 3. Load DimProduct (Clean malformed names, quotes, brackets)
INSERT IGNORE INTO DimProduct (Product_Key, Product_Name)
SELECT 
    CAST(TRIM(Product_Key) AS UNSIGNED),
    TRIM(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(Product_Name, ']', ''), 
                '[', ''), 
            '''', ''),
        '"', '')
    ) AS Product_Name
FROM stg_DimProduct
WHERE Product_Key IS NOT NULL AND TRIM(Product_Key) != '';

-- 4. Load DimPromotion (Handle NULLs and Boolean conversions)
INSERT IGNORE INTO DimPromotion (Promotion_Key, Promotion, Discount_Applied)
SELECT 
    CAST(TRIM(Promotion_Key) AS UNSIGNED),
    COALESCE(NULLIF(TRIM(Promotion), ''), 'No Promotion') AS Promotion,
    CASE 
        WHEN UPPER(TRIM(Discount_Applied)) = 'TRUE' THEN TRUE
        WHEN UPPER(TRIM(Discount_Applied)) = 'FALSE' THEN FALSE
        ELSE FALSE 
    END AS Discount_Applied
FROM stg_DimPromotion
WHERE Promotion_Key IS NOT NULL AND TRIM(Promotion_Key) != '';

-- If a record is completely missing a promo, ensure a default "No Promotion" key exists
INSERT IGNORE INTO DimPromotion (Promotion_Key, Promotion, Discount_Applied)
VALUES (-1, 'No Promotion', FALSE);

-- 5. Load DimStore
INSERT IGNORE INTO DimStore (Store_Key, City, Store_Type)
SELECT 
    CAST(TRIM(Store_Key) AS UNSIGNED),
    TRIM(City),
    TRIM(Store_Type)
FROM stg_DimStore
WHERE Store_Key IS NOT NULL AND TRIM(Store_Key) != '';

-- 6. Load FactSales
-- Maps the staging date key (timestamp-based) to the new Date Grain YYYYMMDD key.
INSERT IGNORE INTO FactSales (Transaction_ID, Date_Key, Customer_Key, Store_Key, Promotion_Key, Total_Items, Total_Cost)
SELECT 
    CAST(TRIM(fs.Transaction_ID) AS UNSIGNED),
    CAST(DATE_FORMAT(CAST(LEFT(d.Full_Date, 10) AS DATE), '%Y%m%d') AS UNSIGNED) AS Date_Key,
    CAST(TRIM(fs.Customer_Key) AS UNSIGNED),
    CAST(TRIM(fs.Store_Key) AS UNSIGNED),
    COALESCE(CAST(NULLIF(TRIM(fs.Promotion_Key), '') AS UNSIGNED), -1) AS Promotion_Key,
    CAST(TRIM(fs.Total_Items) AS UNSIGNED),
    CAST(TRIM(fs.Total_Cost) AS DECIMAL(10,2))
FROM stg_FactSales fs
LEFT JOIN stg_DimDate d ON fs.Date_Key = d.Date_Key
WHERE fs.Transaction_ID IS NOT NULL AND TRIM(fs.Transaction_ID) != '';

-- 7. Load FactProductBridge
INSERT IGNORE INTO FactProductBridge (Transaction_ID, Product_Key)
SELECT 
    CAST(TRIM(Transaction_ID) AS UNSIGNED),
    CAST(TRIM(Product_Key) AS UNSIGNED)
FROM stg_FactProductBridge
WHERE Transaction_ID IS NOT NULL AND TRIM(Transaction_ID) != ''
  AND Product_Key IS NOT NULL AND TRIM(Product_Key) != '';

-- ============================================================================
-- DATA QUALITY ANALYSIS QUERIES
-- ============================================================================

-- 1. Missing values by table (Count comparisons between staging and final)
SELECT 'DimCustomer' AS Table_Name, (SELECT COUNT(*) FROM stg_DimCustomer) - (SELECT COUNT(*) FROM DimCustomer) AS Dropped_Rows
UNION ALL SELECT 'DimProduct', (SELECT COUNT(*) FROM stg_DimProduct) - (SELECT COUNT(*) FROM DimProduct)
UNION ALL SELECT 'FactSales', (SELECT COUNT(*) FROM stg_FactSales) - (SELECT COUNT(*) FROM FactSales);

-- 2. Missing values by column / Null percentages in FactSales
SELECT 
    SUM(CASE WHEN Customer_Key IS NULL THEN 1 ELSE 0 END) / COUNT(*) * 100 AS Null_Pct_Customer,
    SUM(CASE WHEN Store_Key IS NULL THEN 1 ELSE 0 END) / COUNT(*) * 100 AS Null_Pct_Store,
    SUM(CASE WHEN Promotion_Key = -1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS Pct_No_Promotion
FROM FactSales;

-- 3. Duplicate key detection in Dimension Tables (Should be 0 due to PKs, but checks source)
SELECT Customer_Key, COUNT(*) as Occurrences 
FROM stg_DimCustomer GROUP BY Customer_Key HAVING COUNT(*) > 1;

-- 4. Foreign key validation / Invalid references (Orphaned Facts)
SELECT COUNT(*) AS Orphaned_Sales_Customer FROM FactSales f LEFT JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key WHERE c.Customer_Key IS NULL;
SELECT COUNT(*) AS Orphaned_Sales_Store FROM FactSales f LEFT JOIN DimStore s ON f.Store_Key = s.Store_Key WHERE s.Store_Key IS NULL;

-- 5. Revenue outlier detection (Transactions > 3 standard deviations from mean)
SELECT Transaction_ID, Total_Cost 
FROM FactSales 
WHERE Total_Cost > (SELECT AVG(Total_Cost) + (3 * STDDEV(Total_Cost)) FROM FactSales);

-- 6. Product count distribution (Check bridge table anomaly)
SELECT Transaction_ID, COUNT(Product_Key) AS Product_Count 
FROM FactProductBridge GROUP BY Transaction_ID ORDER BY Product_Count DESC LIMIT 10;

-- 7. Customer category distribution
SELECT Customer_Category, COUNT(*) AS Customer_Count FROM DimCustomer GROUP BY Customer_Category;

-- 8. Store distribution
SELECT City, Store_Type, COUNT(*) AS Store_Count FROM DimStore GROUP BY City, Store_Type;

-- 9. Promotion quality checks (Distribution of discounts)
SELECT Promotion, Discount_Applied, COUNT(*) AS Times_Applied 
FROM DimPromotion GROUP BY Promotion, Discount_Applied;

-- 10. Data completeness check (Date ranges)
SELECT MIN(Full_Date) AS Earliest_Date, MAX(Full_Date) AS Latest_Date, COUNT(DISTINCT Date_Key) AS Total_Days FROM DimDate;

-- ============================================================================
-- BUSINESS ANALYTICS (EDA) - 25 QUERIES
-- ============================================================================

-- Q1: Total Revenue
SELECT SUM(Total_Cost) AS Total_Revenue FROM FactSales;

-- Q2: Total Transactions
SELECT COUNT(DISTINCT Transaction_ID) AS Total_Transactions FROM FactSales;

-- Q3: Average Order Value
SELECT AVG(Total_Cost) AS Average_Order_Value FROM FactSales;

-- Q4: Average Basket Size (Items per transaction)
SELECT AVG(Total_Items) AS Average_Basket_Size FROM FactSales;

-- Q5: Revenue by Year
SELECT d.Year, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimDate d ON f.Date_Key = d.Date_Key 
GROUP BY d.Year ORDER BY d.Year;

-- Q6: Revenue by Quarter
SELECT d.Year, d.Quarter, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimDate d ON f.Date_Key = d.Date_Key 
GROUP BY d.Year, d.Quarter ORDER BY d.Year, d.Quarter;

-- Q7: Revenue by Month
SELECT d.Year, d.Month_Name, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimDate d ON f.Date_Key = d.Date_Key 
GROUP BY d.Year, d.Month, d.Month_Name ORDER BY d.Year, d.Month;

-- Q8: Revenue by Season
SELECT d.Season, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimDate d ON f.Date_Key = d.Date_Key 
GROUP BY d.Season ORDER BY Revenue DESC;

-- Q9: Revenue by Customer Category
SELECT c.Customer_Category, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key 
GROUP BY c.Customer_Category ORDER BY Revenue DESC;

-- Q10: Top 10 Customers by Revenue
SELECT c.Customer_Name, SUM(f.Total_Cost) AS Total_Spent 
FROM FactSales f JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key 
GROUP BY c.Customer_Name ORDER BY Total_Spent DESC LIMIT 10;

-- Q11: Customer Segments (RFM approximation based on spending)
SELECT c.Customer_Name, SUM(f.Total_Cost) AS Total_Spent,
    CASE 
        WHEN SUM(f.Total_Cost) > 500 THEN 'High Value'
        WHEN SUM(f.Total_Cost) BETWEEN 100 AND 500 THEN 'Medium Value'
        ELSE 'Low Value' 
    END AS Customer_Segment
FROM FactSales f JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key 
GROUP BY c.Customer_Name;

-- Q12: Customer Category Contribution %
SELECT c.Customer_Category, SUM(f.Total_Cost) AS Revenue,
       (SUM(f.Total_Cost) / (SELECT SUM(Total_Cost) FROM FactSales)) * 100 AS Contribution_Pct
FROM FactSales f JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key 
GROUP BY c.Customer_Category;

-- Q13: Revenue by City
SELECT s.City, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimStore s ON f.Store_Key = s.Store_Key 
GROUP BY s.City ORDER BY Revenue DESC;

-- Q14: Revenue by Store Type
SELECT s.Store_Type, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimStore s ON f.Store_Key = s.Store_Key 
GROUP BY s.Store_Type ORDER BY Revenue DESC;

-- Q15: Best Performing Cities
SELECT s.City, COUNT(f.Transaction_ID) AS Total_Transactions, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimStore s ON f.Store_Key = s.Store_Key 
GROUP BY s.City ORDER BY Revenue DESC LIMIT 5;

-- Q16: Best Performing Store Types
SELECT s.Store_Type, AVG(f.Total_Cost) AS Avg_Transaction_Value 
FROM FactSales f JOIN DimStore s ON f.Store_Key = s.Store_Key 
GROUP BY s.Store_Type ORDER BY Avg_Transaction_Value DESC LIMIT 5;

-- Q17: Revenue by Promotion
SELECT p.Promotion, SUM(f.Total_Cost) AS Revenue 
FROM FactSales f JOIN DimPromotion p ON f.Promotion_Key = p.Promotion_Key 
GROUP BY p.Promotion ORDER BY Revenue DESC;

-- Q18: Promotion Impact (Transactions with vs without Promo)
SELECT 
    CASE WHEN p.Promotion = 'No Promotion' THEN 'Without Promo' ELSE 'With Promo' END AS Promo_Status,
    COUNT(f.Transaction_ID) AS Transactions, 
    SUM(f.Total_Cost) AS Total_Revenue
FROM FactSales f JOIN DimPromotion p ON f.Promotion_Key = p.Promotion_Key 
GROUP BY Promo_Status;

-- Q19: Discount Effectiveness (Does TRUE discount increase Avg Basket Size?)
SELECT p.Discount_Applied, AVG(f.Total_Items) AS Avg_Basket_Size, AVG(f.Total_Cost) AS Avg_Order_Value
FROM FactSales f JOIN DimPromotion p ON f.Promotion_Key = p.Promotion_Key 
GROUP BY p.Discount_Applied;

-- Q20: Top 10 Products by Volume
SELECT p.Product_Name, COUNT(b.Transaction_ID) AS Times_Purchased 
FROM FactProductBridge b JOIN DimProduct p ON b.Product_Key = p.Product_Key 
GROUP BY p.Product_Name ORDER BY Times_Purchased DESC LIMIT 10;

-- Q21: Lowest 10 Products by Volume
SELECT p.Product_Name, COUNT(b.Transaction_ID) AS Times_Purchased 
FROM FactProductBridge b JOIN DimProduct p ON b.Product_Key = p.Product_Key 
GROUP BY p.Product_Name ORDER BY Times_Purchased ASC LIMIT 10;

-- Q22: Product Popularity Ranking (Window Function)
SELECT p.Product_Name, COUNT(b.Transaction_ID) AS Total_Purchases,
       DENSE_RANK() OVER (ORDER BY COUNT(b.Transaction_ID) DESC) AS Popularity_Rank
FROM FactProductBridge b JOIN DimProduct p ON b.Product_Key = p.Product_Key 
GROUP BY p.Product_Name;

-- Q23: Seasonal Product Trends
SELECT d.Season, p.Product_Name, COUNT(b.Transaction_ID) AS Purchases 
FROM FactProductBridge b 
JOIN FactSales f ON b.Transaction_ID = f.Transaction_ID
JOIN DimDate d ON f.Date_Key = d.Date_Key
JOIN DimProduct p ON b.Product_Key = p.Product_Key
GROUP BY d.Season, p.Product_Name 
ORDER BY d.Season, Purchases DESC;

-- Q24: Revenue Growth (Month-over-Month via LAG)
WITH MonthlyRev AS (
    SELECT d.Year, d.Month, SUM(f.Total_Cost) AS Revenue
    FROM FactSales f JOIN DimDate d ON f.Date_Key = d.Date_Key
    GROUP BY d.Year, d.Month
)
SELECT Year, Month, Revenue,
       LAG(Revenue) OVER(ORDER BY Year, Month) AS Prev_Month_Rev,
       ((Revenue - LAG(Revenue) OVER(ORDER BY Year, Month)) / LAG(Revenue) OVER(ORDER BY Year, Month)) * 100 AS MoM_Growth_Pct
FROM MonthlyRev;

-- Q25: Cross-Selling / Product Affinity (Products bought together)
SELECT p1.Product_Name AS Product_A, p2.Product_Name AS Product_B, COUNT(*) AS Co_occurrence_Count
FROM FactProductBridge b1
JOIN FactProductBridge b2 ON b1.Transaction_ID = b2.Transaction_ID AND b1.Product_Key < b2.Product_Key
JOIN DimProduct p1 ON b1.Product_Key = p1.Product_Key
JOIN DimProduct p2 ON b2.Product_Key = p2.Product_Key
GROUP BY p1.Product_Name, p2.Product_Name
ORDER BY Co_occurrence_Count DESC LIMIT 10;

-- ============================================================================
-- POWER BI VIEWS
-- ============================================================================

-- View: Sales Overview
CREATE OR REPLACE VIEW vw_SalesOverview AS
SELECT 
    f.Transaction_ID, d.Full_Date, d.Year, d.Month_Name,
    c.Customer_Name, c.Customer_Category,
    s.City, s.Store_Type,
    p.Promotion, p.Discount_Applied,
    f.Total_Items, f.Total_Cost
FROM FactSales f
JOIN DimDate d ON f.Date_Key = d.Date_Key
JOIN DimCustomer c ON f.Customer_Key = c.Customer_Key
JOIN DimStore s ON f.Store_Key = s.Store_Key
JOIN DimPromotion p ON f.Promotion_Key = p.Promotion_Key;

-- View: Customer Analysis
CREATE OR REPLACE VIEW vw_CustomerAnalysis AS
SELECT 
    c.Customer_Key, c.Customer_Name, c.Customer_Category,
    COUNT(DISTINCT f.Transaction_ID) AS Total_Orders,
    SUM(f.Total_Cost) AS Total_Spent,
    AVG(f.Total_Cost) AS Average_Order_Value
FROM DimCustomer c
LEFT JOIN FactSales f ON c.Customer_Key = f.Customer_Key
GROUP BY c.Customer_Key, c.Customer_Name, c.Customer_Category;

-- View: Product Performance
CREATE OR REPLACE VIEW vw_ProductPerformance AS
SELECT 
    p.Product_Key, p.Product_Name,
    COUNT(b.Transaction_ID) AS Total_Units_Sold,
    COUNT(DISTINCT f.Customer_Key) AS Unique_Customers
FROM DimProduct p
LEFT JOIN FactProductBridge b ON p.Product_Key = b.Product_Key
LEFT JOIN FactSales f ON b.Transaction_ID = f.Transaction_ID
GROUP BY p.Product_Key, p.Product_Name;

-- View: Promotion Analysis
CREATE OR REPLACE VIEW vw_PromotionAnalysis AS
SELECT 
    p.Promotion_Key, p.Promotion, p.Discount_Applied,
    COUNT(f.Transaction_ID) AS Times_Used,
    SUM(f.Total_Cost) AS Generated_Revenue
FROM DimPromotion p
LEFT JOIN FactSales f ON p.Promotion_Key = f.Promotion_Key
GROUP BY p.Promotion_Key, p.Promotion, p.Discount_Applied;

-- View: Store Performance
CREATE OR REPLACE VIEW vw_StorePerformance AS
SELECT 
    s.Store_Key, s.City, s.Store_Type,
    COUNT(f.Transaction_ID) AS Total_Transactions,
    SUM(f.Total_Cost) AS Total_Revenue,
    AVG(f.Total_Items) AS Avg_Basket_Size
FROM DimStore s
LEFT JOIN FactSales f ON s.Store_Key = f.Store_Key
GROUP BY s.Store_Key, s.City, s.Store_Type;

-- View: Time Analysis
CREATE OR REPLACE VIEW vw_TimeAnalysis AS
SELECT 
    d.Full_Date, d.Day, d.Month_Name, d.Quarter, d.Year, d.Season,
    COUNT(f.Transaction_ID) AS Daily_Transactions,
    SUM(f.Total_Cost) AS Daily_Revenue
FROM DimDate d
LEFT JOIN FactSales f ON d.Date_Key = f.Date_Key
GROUP BY d.Full_Date, d.Day, d.Month_Name, d.Quarter, d.Year, d.Season;