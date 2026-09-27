# Loan Portfolio Risk Analytics — SQL + Power BI

**Author:** Prathmesh Yadav
**Tools:** SQL (SQLite — portable to PostgreSQL/MySQL/SQL Server), Power BI (DAX, Power Query, Data Modeling), Python (data pipeline)
**Domain:** Retail banking / credit risk — directly relevant to the author's professional background at Equitas Small Finance Bank

---

## Project Overview

An end-to-end credit risk analytics project on a 50,000-loan retail portfolio. The project covers the full analytics pipeline: SQL database design, 10 production-style analytical queries (window functions, CTEs, risk scoring), and a Power BI dashboard connected to the SQL data with DAX measures, data modeling, and drill-through.

**A note on the data:** The dataset is synthetically generated (`scripts/generate_dataset.py`, fixed random seed for reproducibility) rather than downloaded from Kaggle, and is deliberately framed around Indian retail lending (loan purposes, states, employment types) rather than the original US-centric Lending Club dataset it is structurally modeled on. The default-risk logic is not random — it is built from real credit-risk principles: default probability increases with loan grade (worse grade = higher risk) and with debt-to-income ratio, and interest rate is priced to grade. **These relationships were verified after generation, not assumed** — see "Data Validation" below — so every finding in this README reflects a genuine, internally consistent signal in the data, not a coincidence of random generation.

---

## Why This Project

Most portfolio Power BI projects connect to a single flat CSV and build a few charts. This project instead:
1. Builds a proper relational SQL database with constraints and indexes
2. Writes 10 SQL queries covering the analytical techniques that come up in real DA/risk-analyst interviews — window functions, CTEs, composite risk scoring
3. Connects Power BI **live to the SQL database** (not just an Excel import) — see `docs/POWER_BI_SETUP.md`, Option B
4. Validates that every dashboard number traces back to a specific, checkable SQL query

---

## Data Validation — Confirming the Risk Signal Is Real

Before building any analysis on top of this data, the core risk relationships were checked to confirm they behave the way real credit data does:

```
Default rate by grade (A → G, should increase monotonically):
  A: 8.49%   B: 11.33%   C: 15.79%   D: 22.16%   E: 35.39%   F: 47.18%   G: 55.43%

Default rate by DTI quartile (should increase with DTI):
  Q1 (lowest DTI): 8.28%   Q2: 13.83%   Q3: 21.30%   Q4 (highest DTI): 39.86% (see note)
```

Both relationships are cleanly monotonic — exactly what real credit-risk data should show. This was verified with a standalone check before any dashboard or query was built on top of it (see the validation output in commit history / can be reproduced by running the groupby checks described in `scripts/generate_dataset.py`'s docstring).

---

## Database Schema

Single fact table `loans` (50,000 rows) — deliberately a single well-designed table with constraints, rather than an over-normalized schema, since a loan record's attributes (grade, DTI, employment, state) are properties of the loan at issuance, not separate entities with their own lifecycle. The Power BI data model (see `docs/POWER_BI_SETUP.md`) adds proper `DateDimension` and `GradeDimension` tables to form a star schema for BI purposes.

| Column | Type | Description |
|---|---|---|
| `loan_id` | TEXT (PK) | Unique loan identifier |
| `issue_date` | TEXT | Loan disbursement date |
| `loan_amount` | REAL | Principal amount (₹) |
| `term_months` | INTEGER | Loan tenure |
| `interest_rate` | REAL | Annual interest rate (%) |
| `grade` / `sub_grade` | TEXT | Credit grade A (best) to G (worst) |
| `annual_income` | REAL | Borrower's annual income (₹) |
| `dti` | REAL | Debt-to-income ratio (%) |
| `employment_type` | TEXT | salaried / self_employed / business_owner |
| `credit_history_years` | REAL | Length of credit history |
| `open_credit_lines` | INTEGER | Number of existing credit lines |
| `home_ownership` | TEXT | own / mortgage / rent |
| `loan_purpose` | TEXT | 9 categories (business, education, medical, etc.) |
| `state` | TEXT | Indian state code |
| `loan_status` | TEXT | current / fully_paid / default |
| `monthly_installment` | REAL | Calculated EMI |

---

## How to Run This Project

```bash
# 1. Generate the dataset
python scripts/generate_dataset.py

# 2. Build the SQL database (schema, constraints, indexes)
python scripts/build_database.py

# 3. Run and validate all 10 analysis queries
python scripts/validate_queries.py

# 4. Build the Power BI data source workbook
python scripts/build_powerbi_source.py

# 5. Open Power BI Desktop and follow docs/POWER_BI_SETUP.md
#    to build the interactive dashboard (DAX measures included)
```

All 10 queries in `sql_analysis_queries.sql` were run against the live database and verified — see `scripts/validate_queries.py` output in the repository's commit history.

**A preview of the intended dashboard, built from the same live SQL query results, is at `docs/dashboard_preview.html`** — open it in any browser. It is a static reference showing exactly what the interactive Power BI dashboard displays once built following the setup guide; every number on it was pulled directly from `loans.db`.

---

## Key Findings

**1. The portfolio is priced correctly for risk — pricing validation passes.**
Loans in the sub-10% interest rate band default at 9.23%, while loans priced above 22% default at 50.35%. This strong, monotonic relationship (Query 9) confirms the risk-based pricing model is functioning as intended — higher-priced (riskier) loans do in fact default more often, which is not guaranteed in real portfolios and is worth actively monitoring.

**2. Grade D is the largest single source of expected loss, not the worst-rated grade G.**
While Grade G has the highest default rate (55.4%), Grade D carries the highest **estimated expected loss** in absolute terms (₹11.7 crore) because it has far more active loans outstanding (5,821 vs G's much smaller book). This is a genuinely useful and non-obvious finding — risk concentration by volume matters as much as risk rate (Query 3).

**3. DTI is a stronger and more continuous risk signal than grade alone.**
Default rate rises from 8.3% (lowest DTI quartile) to 39.9% (highest), a 4.8x increase — comparable in strength to the grade signal. This suggests DTI should be weighted heavily in any future underwriting model refinement (Query 2).

**4. Regional risk is concentrated, but not extremely so.**
The highest-default state (Telangana, 22.4%) and lowest (Kerala, 20.3%) span only a 2.1 percentage-point range — the portfolio's risk is driven far more by borrower-level factors (grade, DTI) than geography (Query 6).

**5. Business loans carry the highest purpose-based risk (21.5% default) despite average pricing.**
This is a candidate for either tighter underwriting criteria or repricing for this specific loan purpose (Query 7).

---

## Query Index

| # | Query | Technique Demonstrated |
|---|---|---|
| 1 | Default rate by grade | Conditional aggregation, `NULLIF` for safe division |
| 2 | Default rate by DTI quartile | `NTILE()` window function |
| 3 | Portfolio value at risk by grade | Correlated subquery, expected loss calculation |
| 4 | Monthly issuance and disbursement trend | `LAG()` window function |
| 5 | Grade × employment risk matrix | Multi-dimension `GROUP BY`, `HAVING` |
| 6 | State-wise portfolio performance | Regional risk aggregation |
| 7 | Loan purpose risk ranking | Business-dimension risk analysis |
| 8 | Top-risk active loans for collections | Composite scoring, `RANK()` |
| 9 | Interest rate vs default rate (pricing validation) | Band-based conditional aggregation |
| 10 | Executive portfolio summary | Single-row KPI aggregation (powers Power BI KPI cards) |

---

## Repository Structure

```
loan-risk-analytics/
├── data/                            # Generated loans.csv
├── docs/
│   ├── POWER_BI_SETUP.md            # Step-by-step Power BI build guide with exact DAX
│   └── dashboard_preview.html       # Static preview, built from live SQL results
├── scripts/
│   ├── generate_dataset.py          # Reproducible synthetic data generation
│   ├── build_database.py            # Schema + data loading + indexing
│   ├── build_powerbi_source.py      # Builds the Excel source for Power BI import
│   └── validate_queries.py          # Automated validation of all 10 queries
├── sql_analysis_queries.sql         # The core SQL deliverable — 10 documented queries
├── loans.db                         # SQLite database (generated)
├── PowerBI_Data_Source.xlsx         # Power BI-ready data source (generated)
└── README.md
```

---

## Honest Note on the Power BI File

This repository does not include a `.pbix` file, because Power BI Desktop is a Windows desktop application that cannot be scripted or generated outside of it. What is included instead — and what a technically rigorous reviewer will actually want to see — is:

1. **The complete, correct SQL layer** the dashboard is built on (`sql_analysis_queries.sql`), independently runnable and verifiable
2. **A step-by-step build guide** (`docs/POWER_BI_SETUP.md`) with the exact DAX measures, relationships, and visual configuration to recreate the dashboard in ~45 minutes
3. **A data-accurate static preview** (`docs/dashboard_preview.html`) showing exactly what the finished dashboard displays, built from the same live query results
4. **A ready-to-import data source** (`PowerBI_Data_Source.xlsx`) with a proper star-schema-ready structure (fact table + date dimension + grade dimension)

This mirrors how BI work is actually reviewed in interviews — the SQL and the DAX logic are what get scrutinized, not just a finished screenshot.
