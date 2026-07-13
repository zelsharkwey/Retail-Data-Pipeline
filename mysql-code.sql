-- ========================================================================
-- Project: Building a Data Warehouse for Retail Store on Azure Synapse
-- Date: July 2026
-- Prepared by: Project Team
-- Objective: Transform raw data into an analysis-ready Data Warehouse for Power BI
-- ========================================================================

-- ========================================================================
-- Phase 1: Basic Initialization (Configuration & Schemas)
-- ========================================================================

-- Create Schemas
CREATE SCHEMA dw;
GO
CREATE SCHEMA stg;
GO

-- Database Master Key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'P@ssw0rd123456!';
GO

-- Database Scoped Credential for ADLS Gen2 (Managed Identity)
CREATE DATABASE SCOPED CREDENTIAL ADLS_Credential
WITH IDENTITY = 'Managed Identity';
GO

-- External Data Source
CREATE EXTERNAL DATA SOURCE ADLS_Gold
WITH (
    LOCATION = 'abfss://retail@knoledgers.dfs.core.windows.net',
    CREDENTIAL = ADLS_Credential
);
GO

-- External File Format
CREATE EXTERNAL FILE FORMAT CSV_Format
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"'
    )
);
GO

-- ========================================================================
-- Phase 2: External Tables (Staging Tables)
-- ========================================================================

-- External Customer Table
CREATE EXTERNAL TABLE stg.ext_DimCustomer (
    Customer_Key NVARCHAR(50),
    Customer_Name NVARCHAR(255),
    Customer_Category NVARCHAR(100)
)
WITH (
    LOCATION = 'gold/DimCustomer/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Date Table
CREATE EXTERNAL TABLE stg.ext_DimDate (
    Date_Key NVARCHAR(50),
    Full_Date NVARCHAR(100),
    Day NVARCHAR(50),
    Month NVARCHAR(50),
    Month_Name NVARCHAR(50),
    Quarter NVARCHAR(50),
    Year NVARCHAR(50),
    Season NVARCHAR(50)
)
WITH (
    LOCATION = 'gold/DimDate/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Product Table
CREATE EXTERNAL TABLE stg.ext_DimProduct (
    Product_Key NVARCHAR(50),
    Product_Name NVARCHAR(255)
)
WITH (
    LOCATION = 'gold/DimProduct/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Promotion Table
CREATE EXTERNAL TABLE stg.ext_DimPromotion (
    Promotion_Key NVARCHAR(50),
    Promotion NVARCHAR(255),
    Discount_Applied NVARCHAR(50)
)
WITH (
    LOCATION = 'gold/DimPromotion/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Store Table
CREATE EXTERNAL TABLE stg.ext_DimStore (
    Store_Key NVARCHAR(50),
    City NVARCHAR(100),
    Store_Type NVARCHAR(100)
)
WITH (
    LOCATION = 'gold/DimStore/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Sales Table (Fact)
CREATE EXTERNAL TABLE stg.ext_FactSales (
    Transaction_ID NVARCHAR(50),
    Date_Key NVARCHAR(50),
    Customer_Key NVARCHAR(50),
    Store_Key NVARCHAR(50),
    Promotion_Key NVARCHAR(50),
    Total_Items NVARCHAR(50),
    Total_Cost NVARCHAR(50)
)
WITH (
    LOCATION = 'gold/FactSales/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- External Product Bridge Table (Bridge)
CREATE EXTERNAL TABLE stg.ext_FactProductBridge (
    Transaction_ID NVARCHAR(50),
    Product_Key NVARCHAR(50)
)
WITH (
    LOCATION = 'gold/FactProductBridge/',
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- ========================================================================
-- Phase 3: Final Tables (Data Warehouse Tables)
-- ========================================================================

-- Dimension Table: Customers
CREATE TABLE dw.DimCustomer (
    Customer_Key INT NOT NULL,
    Customer_Name NVARCHAR(255),
    Customer_Category NVARCHAR(100)
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- Dimension Table: Dates
CREATE TABLE dw.DimDate (
    Date_Key INT NOT NULL,
    Full_Date DATE,
    Day INT,
    Month INT,
    Month_Name NVARCHAR(50),
    Quarter INT,
    Year INT,
    Season NVARCHAR(50)
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- Dimension Table: Products
CREATE TABLE dw.DimProduct (
    Product_Key INT NOT NULL,
    Product_Name NVARCHAR(255)
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- Dimension Table: Promotions
CREATE TABLE dw.DimPromotion (
    Promotion_Key INT NOT NULL,
    Promotion NVARCHAR(255),
    Discount_Applied BIT
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- Dimension Table: Stores
CREATE TABLE dw.DimStore (
    Store_Key INT NOT NULL,
    City NVARCHAR(100),
    Store_Type NVARCHAR(100)
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

-- Fact Table: Sales
CREATE TABLE dw.FactSales (
    Transaction_ID BIGINT NOT NULL,
    Date_Key INT NOT NULL,
    Customer_Key INT NOT NULL,
    Store_Key INT NOT NULL,
    Promotion_Key INT NULL,
    Total_Items INT,
    Total_Cost FLOAT
)
WITH (DISTRIBUTION = HASH(Transaction_ID), CLUSTERED COLUMNSTORE INDEX);
GO

-- Fact Table: Product Bridge
CREATE TABLE dw.FactProductBridge (
    Transaction_ID BIGINT NOT NULL,
    Product_Key INT NOT NULL
)
WITH (DISTRIBUTION = HASH(Transaction_ID), CLUSTERED COLUMNSTORE INDEX);
GO

-- ========================================================================
-- Phase 4: Data Loading (ETL - INSERT INTO)
-- ========================================================================

-- Load Customer Data
INSERT INTO dw.DimCustomer
SELECT 
    TRY_CAST(Customer_Key AS INT),
    Customer_Name,
    Customer_Category
FROM stg.ext_DimCustomer
WHERE TRY_CAST(Customer_Key AS INT) IS NOT NULL
  AND Customer_Name != 'Customer_Name';
GO

-- Load Date Data
INSERT INTO dw.DimDate
SELECT 
    TRY_CAST(Date_Key AS INT),
    TRY_CAST(LEFT(Full_Date, 10) AS DATE),
    TRY_CAST(Day AS INT),
    TRY_CAST(Month AS INT),
    Month_Name,
    TRY_CAST(Quarter AS INT),
    TRY_CAST(Year AS INT),
    Season
FROM stg.ext_DimDate
WHERE TRY_CAST(Date_Key AS INT) IS NOT NULL
  AND Date_Key != 'Date_Key';
GO

-- Load Product Data
INSERT INTO dw.DimProduct
SELECT 
    TRY_CAST(Product_Key AS INT),
    REPLACE(REPLACE(Product_Name, '[', ''), ']', '')
FROM stg.ext_DimProduct
WHERE TRY_CAST(Product_Key AS INT) IS NOT NULL
  AND Product_Name != 'Product_Name';
GO

-- Load Promotion Data
INSERT INTO dw.DimPromotion
SELECT 
    TRY_CAST(Promotion_Key AS INT),
    CASE WHEN Promotion = '(NULL)' OR Promotion IS NULL OR Promotion = 'Promotion' THEN 'No Promotion' ELSE Promotion END,
    CASE 
        WHEN LOWER(Discount_Applied) IN ('true', '1') THEN 1
        WHEN LOWER(Discount_Applied) IN ('false', '0') THEN 0
        ELSE NULL
    END
FROM stg.ext_DimPromotion
WHERE TRY_CAST(Promotion_Key AS INT) IS NOT NULL
  AND Promotion_Key != 'Promotion_Key';
GO

-- Load Store Data
INSERT INTO dw.DimStore
SELECT 
    TRY_CAST(Store_Key AS INT),
    City,
    Store_Type
FROM stg.ext_DimStore
WHERE TRY_CAST(Store_Key AS INT) IS NOT NULL
  AND Store_Key != 'Store_Key';
GO

-- Load Sales Data
INSERT INTO dw.FactSales
SELECT 
    TRY_CAST(Transaction_ID AS BIGINT),
    TRY_CAST(Date_Key AS INT),
    TRY_CAST(Customer_Key AS INT),
    TRY_CAST(Store_Key AS INT),
    CASE WHEN Promotion_Key = '(NULL)' OR Promotion_Key IS NULL OR Promotion_Key = 'Promotion_Key' THEN NULL ELSE TRY_CAST(Promotion_Key AS INT) END,
    TRY_CAST(Total_Items AS INT),
    TRY_CAST(Total_Cost AS FLOAT)
FROM stg.ext_FactSales
WHERE TRY_CAST(Transaction_ID AS BIGINT) IS NOT NULL
  AND Transaction_ID != 'Transaction_ID';
GO

-- Load Product Bridge Data
INSERT INTO dw.FactProductBridge
SELECT 
    TRY_CAST(Transaction_ID AS BIGINT),
    TRY_CAST(Product_Key AS INT)
FROM stg.ext_FactProductBridge
WHERE TRY_CAST(Transaction_ID AS BIGINT) IS NOT NULL
  AND Transaction_ID != 'Transaction_ID';
GO

-- ========================================================================
-- Phase 5: Data Validation
-- ========================================================================

-- 1. Row counts for each table
SELECT 'DimCustomer' AS TableName, COUNT(*) AS RowsCount FROM dw.DimCustomer
UNION ALL SELECT 'DimDate', COUNT(*) FROM dw.DimDate
UNION ALL SELECT 'DimProduct', COUNT(*) FROM dw.DimProduct
UNION ALL SELECT 'DimPromotion', COUNT(*) FROM dw.DimPromotion
UNION ALL SELECT 'DimStore', COUNT(*) FROM dw.DimStore
UNION ALL SELECT 'FactSales', COUNT(*) FROM dw.FactSales
UNION ALL SELECT 'FactProductBridge', COUNT(*) FROM dw.FactProductBridge;
GO

-- 2. Check relationship integrity (Non-null foreign keys)
SELECT 
    (SELECT COUNT(*) FROM dw.FactSales WHERE Customer_Key IS NULL) AS Null_Customer_Keys,
    (SELECT COUNT(*) FROM dw.FactSales WHERE Store_Key IS NULL) AS Null_Store_Keys,
    (SELECT COUNT(*) FROM dw.FactSales WHERE Date_Key IS NULL) AS Null_Date_Keys;
GO

-- 3. Value ranges in Sales table
SELECT 
    MIN(Total_Cost) AS Min_Cost,
    MAX(Total_Cost) AS Max_Cost,
    AVG(Total_Cost) AS Avg_Cost,
    MIN(Total_Items) AS Min_Items,
    MAX(Total_Items) AS Max_Items,
    AVG(Total_Items) AS Avg_Items
FROM dw.FactSales;
GO

-- 4. Customer distribution by category
SELECT Customer_Category, COUNT(*) AS Count
FROM dw.DimCustomer
GROUP BY Customer_Category
ORDER BY Count DESC;
GO

-- 5. Check for primary key duplicates
SELECT 'DimCustomer' AS TableName, COUNT(*) - COUNT(DISTINCT Customer_Key) AS Duplicates FROM dw.DimCustomer
UNION ALL SELECT 'DimDate', COUNT(*) - COUNT(DISTINCT Date_Key) FROM dw.DimDate
UNION ALL SELECT 'DimProduct', COUNT(*) - COUNT(DISTINCT Product_Key) FROM dw.DimProduct
UNION ALL SELECT 'DimPromotion', COUNT(*) - COUNT(DISTINCT Promotion_Key) FROM dw.DimPromotion
UNION ALL SELECT 'DimStore', COUNT(*) - COUNT(DISTINCT Store_Key) FROM dw.DimStore;
GO

-- ========================================================================
-- Phase 6: Core Analytics
-- ========================================================================

-- Total Revenue
SELECT 'Total Revenue' AS Metric, FORMAT(SUM(Total_Cost), 'N0') AS Value
FROM dw.FactSales;
GO

-- Total Transactions
SELECT 'Total Transactions' AS Metric, FORMAT(COUNT(DISTINCT Transaction_ID), 'N0') AS Value
FROM dw.FactSales;
GO

-- Average Order Value (AOV)
SELECT 'Average Order Value' AS Metric, FORMAT(AVG(Total_Cost), 'N2') AS Value
FROM dw.FactSales;
GO

-- Average Basket Size
SELECT 'Avg Basket Size' AS Metric, FORMAT(AVG(CAST(Total_Items AS FLOAT)), 'N2') AS Value
FROM dw.FactSales;
GO

-- Revenue by Year
SELECT d.Year, FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Year
ORDER BY d.Year;
GO

-- Revenue by Season
SELECT d.Season, FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Season
ORDER BY Revenue DESC;
GO

-- Revenue by Customer Category
SELECT c.Customer_Category, FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue
FROM dw.FactSales f
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
GROUP BY c.Customer_Category
ORDER BY Revenue DESC;
GO

-- Revenue by City
SELECT s.City, FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.City
ORDER BY Revenue DESC;
GO

-- Revenue by Store Type
SELECT s.Store_Type, FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.Store_Type
ORDER BY Revenue DESC;
GO

-- Top 10 Best Selling Products
SELECT TOP 10 p.Product_Name, COUNT(pb.Transaction_ID) AS Times_Sold
FROM dw.FactProductBridge pb
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
GROUP BY p.Product_Name
ORDER BY Times_Sold DESC;
GO

-- ========================================================================
-- Phase 7: Advanced Analytics
-- ========================================================================

-- 1. Customer Retention Analysis
WITH CustomerOrders AS (
    SELECT Customer_Key, 
           COUNT(DISTINCT Transaction_ID) AS Order_Count,
           MIN(Date_Key) AS First_Order_Date,
           MAX(Date_Key) AS Last_Order_Date
    FROM dw.FactSales
    GROUP BY Customer_Key
)
SELECT 
    CASE 
        WHEN Order_Count = 1 THEN '1 (New)'
        WHEN Order_Count BETWEEN 2 AND 3 THEN '2-3 (Occasional)'
        WHEN Order_Count BETWEEN 4 AND 6 THEN '4-6 (Regular)'
        WHEN Order_Count BETWEEN 7 AND 10 THEN '7-10 (Loyal)'
        ELSE '10+ (VIP)'
    END AS Customer_Segment,
    COUNT(Customer_Key) AS Num_Customers,
    FORMAT(COUNT(Customer_Key) * 100.0 / SUM(COUNT(Customer_Key)) OVER (), 'N2') AS Pct_Of_Total
FROM CustomerOrders
GROUP BY 
    CASE 
        WHEN Order_Count = 1 THEN '1 (New)'
        WHEN Order_Count BETWEEN 2 AND 3 THEN '2-3 (Occasional)'
        WHEN Order_Count BETWEEN 4 AND 6 THEN '4-6 (Regular)'
        WHEN Order_Count BETWEEN 7 AND 10 THEN '7-10 (Loyal)'
        ELSE '10+ (VIP)'
    END
ORDER BY MIN(Order_Count);
GO

-- 2. Average Days Between Orders (for Repeat Customers)
WITH CustomerOrders AS (
    SELECT 
        f.Customer_Key,
        f.Transaction_ID,
        d.Full_Date AS Order_Date,
        LAG(d.Full_Date, 1) OVER (PARTITION BY f.Customer_Key ORDER BY d.Full_Date) AS Prev_Order_Date
    FROM dw.FactSales f
    JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
),
DaysBetween AS (
    SELECT 
        Customer_Key,
        DATEDIFF(DAY, Prev_Order_Date, Order_Date) AS Days_Between_Orders
    FROM CustomerOrders
    WHERE Prev_Order_Date IS NOT NULL
)
SELECT 
    COUNT(DISTINCT Customer_Key) AS Customers_With_Multiple_Orders,
    AVG(CAST(Days_Between_Orders AS FLOAT)) AS Avg_Days_Between_Orders
FROM DaysBetween;
GO

-- 3. Average Customer Lifespan (From First to Last Order)
WITH CustomerOrders AS (
    SELECT 
        f.Customer_Key, 
        MIN(d.Full_Date) AS First_Order_Date,
        MAX(d.Full_Date) AS Last_Order_Date
    FROM dw.FactSales f
    JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
    GROUP BY f.Customer_Key
)
SELECT 
    'Avg Customer Lifespan (Days)' AS Metric,
    FORMAT(AVG(DATEDIFF(DAY, First_Order_Date, Last_Order_Date)), 'N2') AS Value
FROM CustomerOrders;
GO

-- 4. Products Purchased Together (Market Basket Analysis) using Lift
WITH TotalTransactions AS (
    SELECT COUNT(DISTINCT Transaction_ID) AS Total_Trans
    FROM dw.FactSales
),
ProductFrequency AS (
    SELECT 
        LOWER(TRIM(REPLACE(REPLACE(p.Product_Name, '''', ''), '"', ''))) AS Product_Name,
        COUNT(DISTINCT pb.Transaction_ID) AS Product_Trans_Count
    FROM dw.FactProductBridge pb
    JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
    GROUP BY LOWER(TRIM(REPLACE(REPLACE(p.Product_Name, '''', ''), '"', '')))
),
PairFrequency AS (
    SELECT 
        t1.Product_Name AS Product1,
        t2.Product_Name AS Product2,
        COUNT(DISTINCT t1.Transaction_ID) AS Pair_Trans_Count
    FROM (
        SELECT 
            pb.Transaction_ID,
            LOWER(TRIM(REPLACE(REPLACE(p.Product_Name, '''', ''), '"', ''))) AS Product_Name
        FROM dw.FactProductBridge pb
        JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
    ) t1
    JOIN (
        SELECT 
            pb.Transaction_ID,
            LOWER(TRIM(REPLACE(REPLACE(p.Product_Name, '''', ''), '"', ''))) AS Product_Name
        FROM dw.FactProductBridge pb
        JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
    ) t2 ON t1.Transaction_ID = t2.Transaction_ID
    WHERE t1.Product_Name < t2.Product_Name
    GROUP BY t1.Product_Name, t2.Product_Name
)
SELECT TOP 10
    pf1.Product_Name AS Product1,
    pf2.Product_Name AS Product2,
    pf.Pair_Trans_Count,
    ROUND(pf.Pair_Trans_Count * 100.0 / tt.Total_Trans, 2) AS Support_Pct,
    ROUND(pf.Pair_Trans_Count * 100.0 / pf1.Product_Trans_Count, 2) AS Confidence_Pct,
    ROUND(
        (pf.Pair_Trans_Count * 1.0 / pf1.Product_Trans_Count) / 
        (pf2.Product_Trans_Count * 1.0 / tt.Total_Trans), 
        2
    ) AS Lift
FROM PairFrequency pf
JOIN ProductFrequency pf1 ON pf.Product1 = pf1.Product_Name
JOIN ProductFrequency pf2 ON pf.Product2 = pf2.Product_Name
CROSS JOIN TotalTransactions tt
ORDER BY Lift DESC;
GO

-- 5. Customer Segment Performance by Season
SELECT 
    d.Season,
    c.Customer_Category,
    COUNT(f.Transaction_ID) AS Transactions,
    FORMAT(SUM(f.Total_Cost), 'N0') AS Revenue,
    FORMAT(AVG(f.Total_Cost), 'N2') AS Avg_Order_Value
FROM dw.FactSales f
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Season, c.Customer_Category
ORDER BY d.Season, Revenue DESC;
GO

-- ========================================================================
-- Phase 8: Power BI Ready Views
-- ========================================================================

-- Drop Old Views (If Exists)
DROP VIEW IF EXISTS dw.vw_SalesOverview;
DROP VIEW IF EXISTS dw.vw_CustomerAnalysis;
DROP VIEW IF EXISTS dw.vw_ProductPerformance;
DROP VIEW IF EXISTS dw.vw_PromotionAnalysis;
DROP VIEW IF EXISTS dw.vw_StorePerformance;
DROP VIEW IF EXISTS dw.vw_TimeAnalysis;
GO

-- View 1: Sales Overview
CREATE VIEW dw.vw_SalesOverview AS
SELECT 
    f.Transaction_ID,
    d.Full_Date,
    c.Customer_Name,
    s.City,
    s.Store_Type,
    f.Total_Items,
    f.Total_Cost
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key;
GO

-- View 2: Customer Analysis
CREATE VIEW dw.vw_CustomerAnalysis AS
SELECT 
    c.Customer_Key,
    c.Customer_Name,
    c.Customer_Category,
    COUNT(DISTINCT f.Transaction_ID) AS Total_Transactions,
    SUM(f.Total_Cost) AS Lifetime_Value,
    AVG(f.Total_Cost) AS Average_Order_Value
FROM dw.DimCustomer c
LEFT JOIN dw.FactSales f ON c.Customer_Key = f.Customer_Key
GROUP BY c.Customer_Key, c.Customer_Name, c.Customer_Category;
GO

-- View 3: Product Performance
CREATE VIEW dw.vw_ProductPerformance AS
SELECT 
    p.Product_Key,
    p.Product_Name,
    COUNT(pb.Transaction_ID) AS Total_Times_Purchased,
    COUNT(DISTINCT f.Customer_Key) AS Unique_Customers_Bought
FROM dw.DimProduct p
LEFT JOIN dw.FactProductBridge pb ON p.Product_Key = pb.Product_Key
LEFT JOIN dw.FactSales f ON pb.Transaction_ID = f.Transaction_ID
GROUP BY p.Product_Key, p.Product_Name;
GO

-- View 4: Promotion Analysis
CREATE VIEW dw.vw_PromotionAnalysis AS
SELECT 
    p.Promotion_Key,
    p.Promotion,
    p.Discount_Applied,
    COUNT(f.Transaction_ID) AS Times_Used,
    SUM(f.Total_Cost) AS Generated_Revenue
FROM dw.DimPromotion p
LEFT JOIN dw.FactSales f ON p.Promotion_Key = f.Promotion_Key
GROUP BY p.Promotion_Key, p.Promotion, p.Discount_Applied;
GO

-- View 5: Store Performance
CREATE VIEW dw.vw_StorePerformance AS
SELECT 
    s.Store_Key,
    s.City,
    s.Store_Type,
    SUM(f.Total_Cost) AS Total_Revenue,
    COUNT(f.Transaction_ID) AS Transaction_Count,
    AVG(f.Total_Items) AS Avg_Basket_Size
FROM dw.DimStore s
LEFT JOIN dw.FactSales f ON s.Store_Key = f.Store_Key
GROUP BY s.Store_Key, s.City, s.Store_Type;
GO

-- View 6: Time Analysis
CREATE VIEW dw.vw_TimeAnalysis AS
SELECT 
    d.Full_Date,
    d.Year,
    d.Quarter,
    d.Month_Name,
    d.Season,
    SUM(f.Total_Cost) AS Daily_Revenue,
    COUNT(f.Transaction_ID) AS Daily_Transactions
FROM dw.DimDate d
LEFT JOIN dw.FactSales f ON d.Date_Key = f.Date_Key
GROUP BY d.Full_Date, d.Year, d.Quarter, d.Month_Name, d.Season;
GO

-- ========================================================================
-- Testing Views (Read first 10 rows)
-- ========================================================================
SELECT TOP 10 * FROM dw.vw_SalesOverview;
SELECT TOP 10 * FROM dw.vw_CustomerAnalysis;
SELECT TOP 10 * FROM dw.vw_ProductPerformance;
SELECT TOP 10 * FROM dw.vw_PromotionAnalysis;
SELECT TOP 10 * FROM dw.vw_StorePerformance;
SELECT TOP 10 * FROM dw.vw_TimeAnalysis;
GO

-- ========================================================================
-- End of Project
-- ========================================================================
