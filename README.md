# Consulting-Delivery-Performance-Analysis
SQL Case Study – Consulting Delivery Performance, Employee Productivity, Resource Allocation, Compensation and Business Risk Analysis using MySQL.


#  Consulting Delivery Performance – Workforce & Resource Allocation Case Study (MySQL)

A SQL case study on a consulting firm's project-level delivery data. It benchmarks employee productivity under different project conditions, tracks performance trajectories, models staffing reallocation scenarios, checks promotion alignment, and finishes with an executive risk prioritization.

![MySQL](https://img.shields.io/badge/MySQL-8.0+-4479A1?logo=mysql&logoColor=white)
![SQL](https://img.shields.io/badge/Language-SQL-orange)
![Status](https://img.shields.io/badge/Status-Completed-brightgreen)

---

##  Project Overview

| Item | Details |
|---|---|
| **Database** | MySQL 8.0+ |
| **Database name** | `case_study_2` |
| **Source table** | `consulting_delivery_performance` |
| **Script** | `Consulting_delivery_performance.sql` |
| **Domain** | Professional Services / Workforce Analytics |
| **Questions solved** | 5 (with step-by-step queries) |

The case study answers questions a consulting firm's leadership would ask: *Who is truly productive once project complexity and client tier are taken into account? Whose quality is quietly declining? Where would moving delivery hours increase contribution? Are promotions aligned with performance? Which findings are robust and which depend on how we benchmark?*

---

## Data Used

The script works on one flat table: `consulting_delivery_performance` (one row per employee-project record).

| Column | Meaning |
|---|---|
| `record_id` | Unique project record identifier |
| `employee_id` | Employee identifier |
| `project_id` | Project identifier |
| `department` | Employee's department |
| `job_level` | Employee's job level |
| `client_tier` | Tier of the client served |
| `project_complexity` | Complexity of the project |
| `project_start_date` | Project start date |
| `billable_hours` | Hours billed to the client |
| `non_billable_hours` | Internal / non-billed hours |
| `rework_hours` | Hours spent on rework |
| `recognized_revenue` | Revenue recognized on the record |
| `delivery_cost` | Cost of delivering the work |
| `quality_score` | Quality rating of the delivery |
| `promotion_date` | Date of the employee's latest promotion |
| `employee_status` | Active / Exited |

> The script does not create or load this table. Import your dataset (for example a CSV) into `case_study_2.consulting_delivery_performance` before running the analysis. Column names must match the ones above.

---

##  Key Metric Definitions

| Metric | Formula |
|---|---|
| **Utilization %** | `billable_hours ÷ (billable_hours + non_billable_hours) × 100` |
| **Revenue per billable hour** | `recognized_revenue ÷ billable_hours` |
| **Contribution proxy** | `recognized_revenue − delivery_cost` |
| **Contribution per billable hour** | Contribution proxy ÷ billable hours |
| **Rework rate %** | `rework_hours ÷ (billable_hours + non_billable_hours) × 100` |
| **Quality score** | Average `quality_score` per employee / segment |

---

##  Business Questions Solved

### Q1 — Productivity Benchmarking Under Heterogeneous Project Conditions
Employee-level utilization, revenue per billable hour, contribution proxy, rework rate and quality. Employees are ranked **company-wide** and within **peer groups** (department, job level, client tier, project complexity). Finds employees in the **top 10% for revenue per billable hour but with below-median quality**, and quantifies how rankings change between company-wide and peer-group comparisons.
*Techniques: `RANK()`, `ROW_NUMBER()`, percentile cut-offs, peer-group partitioning.*

### Q2 — Performance Trajectory & Sustained Underperformance
Employees whose quality score **declines across at least three consecutive project records**, employees whose revenue per billable hour rises while quality-adjusted productivity falls, comparison with the **cumulative department benchmark available at that time**, and flags for apparent improvement driven only by a change in complexity or client tier.
*Techniques: `LAG()`, running averages with window frames, consecutive-record logic, `complexity_tier_flag`.*

### Q3 — Counterfactual Staffing & Resource Allocation
Segments with high delivery cost, elevated rework and below-median quality. Estimates the **contribution change if 10% of delivery hours move** from bottom-performing segments to segments with above-median contribution per billable hour. Departments are ranked, with **sensitivity checks** for (1) all projects, (2) active employees only and (3) projects with at least 100 billable hours.
*Techniques: segment analysis, scenario modelling, `CROSS JOIN` benchmark CTEs, sensitivity scenarios.*

### Q4 — Compensation & Promotion Alignment
Employees whose productivity and quality stay above peer medians but who have **not been promoted in the last three years**, recently promoted employees whose **post-promotion quality is below their job-level median**, and a descriptive comparison of active vs exited employees.
*Techniques: `DATEDIFF`, peer medians, relative productivity, review-list flags.*

### Q5 — Executive Decision Under Uncertainty
Prioritizes resource-allocation risks by department, shows **how risk classifications change under alternative peer groups / benchmarks**, identifies the records affected by each risk, and separates **robust findings from benchmark-sensitive conclusions** in an executive summary.
*Techniques: risk scoring, classification comparison, record-level impact, executive prioritization table.*

---

##  SQL Concepts Used

- Conditional aggregation and safe division (`NULLIF`)
- CTEs (multi-step `WITH` queries)
- Window functions: `RANK()`, `ROW_NUMBER()`, `LAG()`, running `AVG() OVER`
- Peer-group ranking and benchmark comparison
- Date functions: `DATEDIFF`, `CURDATE()`
- Scenario / counterfactual modelling
- Sensitivity analysis across data subsets
- Risk classification with `CASE`

---

##  How to Run

1. Install **MySQL 8.0 or later** (CTEs and window functions are required).
2. Clone the repository:

   ```bash
   git clone https://github.com/<your-username>/<your-repo-name>.git
   cd <your-repo-name>
   ```

3. Create the database and import your data:

   ```sql
   CREATE DATABASE case_study_2;
   USE case_study_2;
   -- Import your dataset into the table `consulting_delivery_performance`
   -- (e.g. using MySQL Workbench → Table Data Import Wizard)
   ```

4. Open `Consulting_delivery_performance.sql` in MySQL Workbench and run it question by question.

>  Each question is split into numbered steps. Run one step at a time to see its intermediate result.

---

##  Notes & Assumptions

- Contribution proxy is **revenue minus delivery cost**. It is a proxy, not audited profit.
- Promotion-recency checks use `CURDATE()`, so results depend on the date the script is run.
- Peer groups combine department, job level, client tier and project complexity.
