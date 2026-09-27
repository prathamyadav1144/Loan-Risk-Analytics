-- ============================================================================
-- LOAN PORTFOLIO RISK ANALYTICS — CORE SQL QUERIES
-- ============================================================================
-- Author: Prathmesh Yadav
-- Database: SQLite (loans.db) — schema also valid on PostgreSQL/MySQL/SQL Server
--
-- These queries power the connected Power BI dashboard (see
-- docs/POWER_BI_SETUP.md). Each query answers a specific credit-risk or
-- portfolio-management business question.
-- ============================================================================


-- QUERY 1: Default Rate by Loan Grade
-- Business question: Does default rate increase monotonically with loan
-- grade, as credit risk theory predicts? (Validates the grading system.)
SELECT
    grade,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END) AS defaults,
    SUM(CASE WHEN loan_status = 'fully_paid' THEN 1 ELSE 0 END) AS fully_paid,
    ROUND(
        100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0),
    2) AS default_rate_pct
FROM loans
GROUP BY grade
ORDER BY grade;


-- QUERY 2: Default Rate by DTI (Debt-to-Income) Quartile
-- Business question: How strongly does DTI predict default risk?
-- Technique: NTILE() to bucket into quartiles, then aggregate
WITH dti_quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY dti) AS dti_quartile
    FROM loans
    WHERE loan_status IN ('default', 'fully_paid')
)
SELECT
    dti_quartile,
    ROUND(MIN(dti), 1) AS dti_min,
    ROUND(MAX(dti), 1) AS dti_max,
    COUNT(*) AS total_loans,
    ROUND(100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM dti_quartiles
GROUP BY dti_quartile
ORDER BY dti_quartile;


-- QUERY 3: Portfolio Value at Risk — Outstanding Exposure by Grade
-- Business question: How much capital is currently at risk in each grade
-- for loans still active ("current" status)?
SELECT
    grade,
    COUNT(*) AS active_loans,
    ROUND(SUM(loan_amount), 2) AS total_exposure,
    ROUND(AVG(loan_amount), 2) AS avg_loan_size,
    ROUND(SUM(loan_amount) * (
        SELECT ROUND(
            100.0 * SUM(CASE WHEN l2.loan_status = 'default' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN l2.loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0), 4
        ) / 100
        FROM loans l2 WHERE l2.grade = loans.grade
    ), 2) AS estimated_expected_loss
FROM loans
WHERE loan_status = 'current'
GROUP BY grade
ORDER BY estimated_expected_loss DESC;


-- QUERY 4: Monthly Loan Issuance and Default Trend
-- Business question: Are recent loan vintages riskier than older ones?
-- Technique: LAG() window function for trend comparison
SELECT
    strftime('%Y-%m', issue_date) AS issue_month,
    COUNT(*) AS loans_issued,
    ROUND(SUM(loan_amount), 2) AS total_disbursed,
    ROUND(AVG(interest_rate), 2) AS avg_interest_rate,
    ROUND(
        SUM(loan_amount) - LAG(SUM(loan_amount)) OVER (ORDER BY strftime('%Y-%m', issue_date)),
    2) AS disbursement_change_mom
FROM loans
GROUP BY issue_month
ORDER BY issue_month;


-- QUERY 5: Risk Segmentation — Grade x Employment Type Matrix
-- Business question: Which combination of grade and employment type has
-- the highest default risk? (Useful for underwriting policy refinement.)
SELECT
    grade,
    employment_type,
    COUNT(*) AS total_loans,
    ROUND(100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0), 2) AS default_rate_pct
FROM loans
GROUP BY grade, employment_type
HAVING SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END) >= 30
ORDER BY default_rate_pct DESC
LIMIT 15;


-- QUERY 6: State-wise Portfolio Performance
-- Business question: Which states have the highest default rates and
-- largest outstanding exposure? (Regional risk concentration check)
SELECT
    state,
    COUNT(*) AS total_loans,
    ROUND(SUM(loan_amount), 2) AS total_disbursed,
    ROUND(100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0), 2) AS default_rate_pct
FROM loans
GROUP BY state
ORDER BY default_rate_pct DESC;


-- QUERY 7: Loan Purpose Risk Ranking
-- Business question: Which loan purposes carry the highest risk, and do
-- they justify their pricing (interest rate)?
SELECT
    loan_purpose,
    COUNT(*) AS total_loans,
    ROUND(AVG(interest_rate), 2) AS avg_interest_rate,
    ROUND(100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0), 2) AS default_rate_pct
FROM loans
GROUP BY loan_purpose
ORDER BY default_rate_pct DESC;


-- QUERY 8: Top-Decile Highest-Risk Active Loans (For Collections Priority)
-- Business question: Which currently active loans have the highest modeled
-- risk and should be prioritized for proactive collections outreach?
-- Technique: Composite risk score + RANK()
WITH risk_scored AS (
    SELECT
        loan_id,
        grade,
        state,
        loan_amount,
        dti,
        credit_history_years,
        -- Simple composite risk score: higher grade letter + higher DTI +
        -- shorter credit history = higher risk. Purely for prioritization,
        -- not a calibrated probability.
        (CASE grade
            WHEN 'A' THEN 1 WHEN 'B' THEN 2 WHEN 'C' THEN 3 WHEN 'D' THEN 4
            WHEN 'E' THEN 5 WHEN 'F' THEN 6 WHEN 'G' THEN 7 END * 10
            + dti * 0.5
            - credit_history_years * 0.3
        ) AS risk_score
    FROM loans
    WHERE loan_status = 'current'
)
SELECT
    loan_id, grade, state, loan_amount, dti, credit_history_years,
    ROUND(risk_score, 2) AS risk_score,
    RANK() OVER (ORDER BY risk_score DESC) AS risk_rank
FROM risk_scored
ORDER BY risk_score DESC
LIMIT 25;


-- QUERY 9: Interest Rate vs Default Rate — Pricing Validation
-- Business question: Is the portfolio priced correctly for risk? (Higher
-- rate bands should show higher default rates — if not, pricing is off.)
WITH rate_bands AS (
    SELECT
        *,
        CASE
            WHEN interest_rate < 10 THEN '1. Under 10%'
            WHEN interest_rate < 14 THEN '2. 10-14%'
            WHEN interest_rate < 18 THEN '3. 14-18%'
            WHEN interest_rate < 22 THEN '4. 18-22%'
            ELSE '5. 22%+'
        END AS rate_band
    FROM loans
    WHERE loan_status IN ('default', 'fully_paid')
)
SELECT
    rate_band,
    COUNT(*) AS total_loans,
    ROUND(AVG(interest_rate), 2) AS avg_rate_in_band,
    ROUND(100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END) / COUNT(*), 2) AS default_rate_pct
FROM rate_bands
GROUP BY rate_band
ORDER BY rate_band;


-- QUERY 10: Portfolio Summary — Key Metrics for Executive Dashboard
-- Business question: What are the headline numbers for a one-page
-- portfolio summary? (This query backs the top KPI cards in Power BI)
SELECT
    COUNT(*) AS total_loans,
    ROUND(SUM(loan_amount), 2) AS total_portfolio_value,
    ROUND(AVG(loan_amount), 2) AS avg_loan_size,
    ROUND(AVG(interest_rate), 2) AS avg_interest_rate,
    SUM(CASE WHEN loan_status = 'current' THEN 1 ELSE 0 END) AS active_loans,
    SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END) AS total_defaults,
    ROUND(
        100.0 * SUM(CASE WHEN loan_status = 'default' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN loan_status IN ('default','fully_paid') THEN 1 ELSE 0 END), 0),
    2) AS overall_default_rate_pct
FROM loans;
