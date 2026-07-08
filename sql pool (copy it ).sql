-- ============================================================================
-- PART 1: CONFIGURATION & SCHEMAS
-- ============================================================================

-- Create dedicated schemas
CREATE SCHEMA dw;
GO
CREATE SCHEMA stg;
GO

-- ============================================================================
-- PART 2: EXTERNAL OBJECTS (ADLS GEN2 CONNECTION)
-- ============================================================================

-- REPLACE_ME: Update the Master Key Password
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'REPLACE_ME_StrongPassword123!';
GO

-- REPLACE_ME: Update the Storage Account Name and Managed Identity/SAS Token
CREATE DATABASE SCOPED CREDENTIAL ADLS_Credential
WITH IDENTITY = 'Managed Identity'; -- Or 'SHARED ACCESS SIGNATURE' with SECRET
GO

-- REPLACE_ME: Update the Storage Account URL and Container
CREATE EXTERNAL DATA SOURCE ADLS_Gold
WITH (
    LOCATION = 'abfss://REPLACE_ME_container@REPLACE_ME_storageaccount.dfs.core.windows.net',
    CREDENTIAL = ADLS_Credential
);
GO

CREATE EXTERNAL FILE FORMAT CSV_Format
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"',
        FIRSTROW = 2,
        USE_TYPE_DEFAULT = FALSE
    )
);
GO

-- ============================================================================
-- PART 3: STAGING TABLES (EXTERNAL TABLES FOR GOLD CSV FILES)
-- ============================================================================
-- Notes: These point directly to the files in ADLS to read them as-is.

-- REPLACE_ME: Adjust LOCATION paths to match your actual ADLS folder names
CREATE EXTERNAL TABLE stg.ext_DimCustomer (
    Customer_Key INT,
    Customer_Name NVARCHAR(255),
    Customer_Category NVARCHAR(100)
)
WITH (
    LOCATION = 'Gold/DimCustomer/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_DimDate (
    Date_Key INT,
    Full_Date NVARCHAR(100),
    Day INT,
    Month INT,
    Month_Name NVARCHAR(50),
    Quarter INT,
    Year INT,
    Season NVARCHAR(50)
)
WITH (
    LOCATION = 'Gold/DimDate/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_DimProduct (
    Product_Key INT,
    Product_Name NVARCHAR(255)
)
WITH (
    LOCATION = 'Gold/DimProduct/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_DimPromotion (
    Promotion_Key INT,
    Promotion NVARCHAR(255),
    Discount_Applied NVARCHAR(50)
)
WITH (
    LOCATION = 'Gold/DimPromotion/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_DimStore (
    Store_Key INT,
    City NVARCHAR(100),
    Store_Type NVARCHAR(100)
)
WITH (
    LOCATION = 'Gold/DimStore/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_FactProductBridge (
    Transaction_ID BIGINT,
    Product_Key INT
)
WITH (
    LOCATION = 'Gold/FactProductBridge/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

CREATE EXTERNAL TABLE stg.ext_FactSales (
    Transaction_ID BIGINT,
    Date_Key INT,
    Customer_Key INT,
    Store_Key INT,
    Promotion_Key INT,
    Total_Items INT,
    Total_Cost FLOAT
)
WITH (
    LOCATION = 'Gold/FactSales/', -- REPLACE_ME
    DATA_SOURCE = ADLS_Gold,
    FILE_FORMAT = CSV_Format
);
GO

-- ============================================================================
-- PART 4: DATA WAREHOUSE TABLES
-- ============================================================================

CREATE TABLE dw.DimCustomer (
    Customer_Key INT NOT NULL,
    Customer_Name NVARCHAR(255),
    Customer_Category NVARCHAR(100)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.DimDate (
    Date_Key INT NOT NULL, -- Will store YYYYMMDD
    Full_Date DATE,
    Day INT,
    Month INT,
    Month_Name NVARCHAR(50),
    Quarter INT,
    Year INT,
    Season NVARCHAR(50)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.DimProduct (
    Product_Key INT NOT NULL,
    Product_Name NVARCHAR(255)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.DimPromotion (
    Promotion_Key INT NOT NULL,
    Promotion NVARCHAR(255),
    Discount_Applied BIT
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.DimStore (
    Store_Key INT NOT NULL,
    City NVARCHAR(100),
    Store_Type NVARCHAR(100)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.FactSales (
    Transaction_ID BIGINT NOT NULL,
    Date_Key INT NOT NULL,
    Customer_Key INT NOT NULL,
    Store_Key INT NOT NULL,
    Promotion_Key INT,
    Total_Items INT,
    Total_Cost FLOAT
)
WITH (
    DISTRIBUTION = HASH(Transaction_ID),
    CLUSTERED COLUMNSTORE INDEX
);
GO

CREATE TABLE dw.FactProductBridge (
    Transaction_ID BIGINT NOT NULL,
    Product_Key INT NOT NULL
)
WITH (
    DISTRIBUTION = HASH(Transaction_ID),
    CLUSTERED COLUMNSTORE INDEX
);
GO

-- ============================================================================
-- PART 5: DATA LOADING & TRANSFORMATION LOGIC
-- ============================================================================

-- Load DimCustomer
INSERT INTO dw.DimCustomer
SELECT 
    Customer_Key,
    TRIM(Customer_Name) AS Customer_Name,
    TRIM(Customer_Category) AS Customer_Category
FROM stg.ext_DimCustomer;
GO

-- Load DimDate (Converting Timestamp to Date Grain & Creating YYYYMMDD Key)
INSERT INTO dw.DimDate
SELECT 
    CAST(FORMAT(CAST(LEFT(Full_Date, 10) AS DATE), 'yyyyMMdd') AS INT) AS Date_Key,
    CAST(LEFT(Full_Date, 10) AS DATE) AS Full_Date,
    MAX(Day) AS Day,
    MAX(Month) AS Month,
    MAX(Month_Name) AS Month_Name,
    MAX(Quarter) AS Quarter,
    MAX(Year) AS Year,
    MAX(Season) AS Season
FROM stg.ext_DimDate
WHERE Full_Date IS NOT NULL
GROUP BY CAST(LEFT(Full_Date, 10) AS DATE);
GO

-- Load DimProduct (Cleaning malformed characters and standardizing casing)
INSERT INTO dw.DimProduct
SELECT 
    Product_Key,
    LOWER(TRIM(REPLACE(REPLACE(Product_Name, ']', ''), '''', ''))) AS Product_Name
FROM stg.ext_DimProduct;
GO

-- Load DimPromotion (Handling NULLs and translating Booleans)
INSERT INTO dw.DimPromotion
SELECT 
    Promotion_Key,
    ISNULL(TRIM(Promotion), 'No Promotion') AS Promotion,
    CASE 
        WHEN UPPER(Discount_Applied) = 'TRUE' THEN 1 
        WHEN UPPER(Discount_Applied) = 'FALSE' THEN 0 
        ELSE 0 
    END AS Discount_Applied
FROM stg.ext_DimPromotion;
GO

-- Load DimStore
INSERT INTO dw.DimStore
SELECT 
    Store_Key,
    TRIM(City) AS City,
    TRIM(Store_Type) AS Store_Type
FROM stg.ext_DimStore;
GO

-- Load FactSales 
-- Note: Joining to staging Date to remap the timestamp-based Date_Key to our new Date Grain Date_Key
INSERT INTO dw.FactSales
SELECT 
    f.Transaction_ID,
    CAST(FORMAT(CAST(LEFT(d.Full_Date, 10) AS DATE), 'yyyyMMdd') AS INT) AS Date_Key,
    f.Customer_Key,
    f.Store_Key,
    ISNULL(f.Promotion_Key, -1) AS Promotion_Key, -- Assuming -1 handles unknown
    f.Total_Items,
    f.Total_Cost
FROM stg.ext_FactSales f
LEFT JOIN stg.ext_DimDate d ON f.Date_Key = d.Date_Key
WHERE f.Transaction_ID IS NOT NULL
AND f.Total_Cost >= 0; -- Validate numeric columns safely
GO

-- Load FactProductBridge
INSERT INTO dw.FactProductBridge
SELECT 
    Transaction_ID,
    Product_Key
FROM stg.ext_FactProductBridge
WHERE Transaction_ID IS NOT NULL AND Product_Key IS NOT NULL;
GO

-- ============================================================================
-- PART 6: DATA QUALITY ANALYSIS QUERIES
-- ============================================================================

-- 1. Missing Values by Table
SELECT 'FactSales' AS TableName, COUNT(*) AS MissingCount FROM dw.FactSales WHERE Total_Cost IS NULL OR Total_Items IS NULL
UNION ALL
SELECT 'DimProduct', COUNT(*) FROM dw.DimProduct WHERE Product_Name IS NULL;

-- 2. NULL Percentages by Column in FactSales
SELECT 
    (COUNT(CASE WHEN Customer_Key IS NULL THEN 1 END) * 100.0 / COUNT(*)) AS PctNull_Customer,
    (COUNT(CASE WHEN Store_Key IS NULL THEN 1 END) * 100.0 / COUNT(*)) AS PctNull_Store,
    (COUNT(CASE WHEN Promotion_Key IS NULL THEN 1 END) * 100.0 / COUNT(*)) AS PctNull_Promotion
FROM dw.FactSales;

-- 3. Duplicate Key Checks
SELECT Product_Key, COUNT(*) AS Occurrences
FROM dw.DimProduct
GROUP BY Product_Key
HAVING COUNT(*) > 1;

-- 4. Referential Integrity Checks (Orphaned Facts)
SELECT COUNT(*) AS Orphaned_Customers
FROM dw.FactSales f
LEFT JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
WHERE c.Customer_Key IS NULL;

-- 5. Invalid Dimension References (Dates outside bound)
SELECT COUNT(*) AS InvalidDates
FROM dw.FactSales f
LEFT JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
WHERE d.Date_Key IS NULL;

-- 6. Revenue Outlier Detection (Z-Score approximation)
WITH Stats AS (
    SELECT AVG(Total_Cost) as AvgCost, STDEV(Total_Cost) as StdDevCost FROM dw.FactSales
)
SELECT f.*
FROM dw.FactSales f
CROSS JOIN Stats s
WHERE f.Total_Cost > (s.AvgCost + (3 * s.StdDevCost));

-- 7. Product Count Distribution (Bridge Table Check)
SELECT Product_Key, COUNT(Transaction_ID) as TimesPurchased
FROM dw.FactProductBridge
GROUP BY Product_Key
ORDER BY TimesPurchased DESC;

-- 8. Customer Distribution by Category
SELECT Customer_Category, COUNT(*) as NumCustomers
FROM dw.DimCustomer
GROUP BY Customer_Category;

-- 9. Store Distribution by City
SELECT City, COUNT(*) as NumStores
FROM dw.DimStore
GROUP BY City;

-- 10. Promotion Usage Quality Checks
SELECT Promotion, Discount_Applied, COUNT(*) as UsageCount
FROM dw.DimPromotion
GROUP BY Promotion, Discount_Applied;

-- ============================================================================
-- PART 7: BUSINESS ANALYTICS QUERIES (EDA)
-- ============================================================================

-- Q1. Total Revenue
SELECT SUM(Total_Cost) AS Total_Revenue FROM dw.FactSales;

-- Q2. Total Transactions
SELECT COUNT(DISTINCT Transaction_ID) AS Total_Transactions FROM dw.FactSales;

-- Q3. Average Order Value (AOV)
SELECT AVG(Total_Cost) AS Average_Order_Value FROM dw.FactSales;

-- Q4. Average Basket Size
SELECT AVG(CAST(Total_Items AS FLOAT)) AS Avg_Basket_Size FROM dw.FactSales;

-- Q5. Revenue by Year
SELECT d.Year, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Year ORDER BY d.Year;

-- Q6. Revenue by Quarter
SELECT d.Year, d.Quarter, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Year, d.Quarter ORDER BY d.Year, d.Quarter;

-- Q7. Revenue by Month
SELECT d.Year, d.Month_Name, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Year, d.Month, d.Month_Name ORDER BY d.Year, d.Month;

-- Q8. Revenue by Season
SELECT d.Season, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Season ORDER BY Revenue DESC;

-- Q9. Revenue by Customer Category
SELECT c.Customer_Category, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
GROUP BY c.Customer_Category ORDER BY Revenue DESC;

-- Q10. Top 10 Customers by Revenue
SELECT TOP 10 c.Customer_Name, SUM(f.Total_Cost) AS Total_Spent
FROM dw.FactSales f
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
GROUP BY c.Customer_Name ORDER BY Total_Spent DESC;

-- Q11. Customer Segment Contribution (%)
WITH CategoryRev AS (
    SELECT c.Customer_Category, SUM(f.Total_Cost) AS Revenue
    FROM dw.FactSales f
    JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
    GROUP BY c.Customer_Category
)
SELECT Customer_Category, Revenue, 
       (Revenue * 100.0 / SUM(Revenue) OVER ()) AS Contribution_Pct
FROM CategoryRev;

-- Q12. Revenue by City
SELECT s.City, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.City ORDER BY Revenue DESC;

-- Q13. Revenue by Store Type
SELECT s.Store_Type, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.Store_Type ORDER BY Revenue DESC;

-- Q14. Top Performing Cities
SELECT TOP 5 s.City, SUM(f.Total_Cost) AS Revenue, COUNT(f.Transaction_ID) AS Transactions
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.City ORDER BY Revenue DESC;

-- Q15. Top Performing Store Types
SELECT TOP 5 s.Store_Type, AVG(f.Total_Cost) AS Avg_Transaction_Value
FROM dw.FactSales f
JOIN dw.DimStore s ON f.Store_Key = s.Store_Key
GROUP BY s.Store_Type ORDER BY Avg_Transaction_Value DESC;

-- Q16. Revenue by Promotion
SELECT p.Promotion, SUM(f.Total_Cost) AS Revenue
FROM dw.FactSales f
JOIN dw.DimPromotion p ON f.Promotion_Key = p.Promotion_Key
GROUP BY p.Promotion ORDER BY Revenue DESC;

-- Q17. Promotion Effectiveness (Avg Items per Promo)
SELECT p.Promotion, AVG(CAST(f.Total_Items AS FLOAT)) AS Avg_Items_Sold
FROM dw.FactSales f
JOIN dw.DimPromotion p ON f.Promotion_Key = p.Promotion_Key
GROUP BY p.Promotion ORDER BY Avg_Items_Sold DESC;

-- Q18. Discount Impact Analysis
SELECT p.Discount_Applied, SUM(f.Total_Cost) AS Total_Revenue, COUNT(f.Transaction_ID) AS Trans_Count
FROM dw.FactSales f
JOIN dw.DimPromotion p ON f.Promotion_Key = p.Promotion_Key
GROUP BY p.Discount_Applied;

-- Q19. Top 10 Products by Frequency
SELECT TOP 10 p.Product_Name, COUNT(pb.Transaction_ID) AS Times_Sold
FROM dw.FactProductBridge pb
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
GROUP BY p.Product_Name ORDER BY Times_Sold DESC;

-- Q20. Bottom 10 Products
SELECT TOP 10 p.Product_Name, COUNT(pb.Transaction_ID) AS Times_Sold
FROM dw.FactProductBridge pb
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
GROUP BY p.Product_Name ORDER BY Times_Sold ASC;

-- Q21. Product Popularity vs Category
SELECT p.Product_Name, c.Customer_Category, COUNT(f.Transaction_ID) AS Purchases
FROM dw.FactSales f
JOIN dw.FactProductBridge pb ON f.Transaction_ID = pb.Transaction_ID
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
GROUP BY p.Product_Name, c.Customer_Category;

-- Q22. Product Revenue Contribution Estimation (Allocating cost equally to items in bridge)
WITH TransactionCost AS (
    SELECT f.Transaction_ID, f.Total_Cost, 
           COUNT(pb.Product_Key) AS Product_Count
    FROM dw.FactSales f
    JOIN dw.FactProductBridge pb ON f.Transaction_ID = pb.Transaction_ID
    GROUP BY f.Transaction_ID, f.Total_Cost
)
SELECT p.Product_Name, SUM(tc.Total_Cost / tc.Product_Count) AS Estimated_Revenue
FROM TransactionCost tc
JOIN dw.FactProductBridge pb ON tc.Transaction_ID = pb.Transaction_ID
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
GROUP BY p.Product_Name ORDER BY Estimated_Revenue DESC;

-- Q23. Seasonal Product Trends
SELECT d.Season, p.Product_Name, COUNT(pb.Transaction_ID) AS Units_Sold
FROM dw.FactSales f
JOIN dw.FactProductBridge pb ON f.Transaction_ID = pb.Transaction_ID
JOIN dw.DimProduct p ON pb.Product_Key = p.Product_Key
JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
GROUP BY d.Season, p.Product_Name
ORDER BY d.Season, Units_Sold DESC;

-- Q24. Revenue Growth Trends (Month over Month)
WITH MonthlyRev AS (
    SELECT d.Year, d.Month, SUM(f.Total_Cost) AS Revenue
    FROM dw.FactSales f
    JOIN dw.DimDate d ON f.Date_Key = d.Date_Key
    GROUP BY d.Year, d.Month
)
SELECT Year, Month, Revenue,
       LAG(Revenue, 1) OVER (ORDER BY Year, Month) AS Prev_Month_Revenue,
       (Revenue - LAG(Revenue, 1) OVER (ORDER BY Year, Month)) / LAG(Revenue, 1) OVER (ORDER BY Year, Month) * 100 AS MoM_Growth_Pct
FROM MonthlyRev;

-- Q25. Customer Purchasing Behavior (Transactions per Customer)
SELECT Customer_Name, Customer_Category, 
       COUNT(Transaction_ID) AS Total_Transactions, 
       SUM(Total_Cost) AS Total_LTV
FROM dw.FactSales f
JOIN dw.DimCustomer c ON f.Customer_Key = c.Customer_Key
GROUP BY Customer_Name, Customer_Category
ORDER BY Total_LTV DESC;

-- ============================================================================
-- PART 8: POWER BI VIEWS
-- ============================================================================

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