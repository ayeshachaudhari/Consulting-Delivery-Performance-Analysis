CREATE DATABASE case_study_2 ;

USE case_study_2 ;

SELECT * FROM `consulting_delivery_performance`;

SHOW TABLES ;

-- 1. Productivity benchmarking under heterogeneous project conditions
/* Calculate employee-level utilization, revenue per billable hour, contribution proxy, rework rate, and quality
score. Rank employees within comparable department, job-level, client-tier, and project-complexity groups.
Identify employees in the top 10% for revenue per billable hour but below median quality, and quantify ranking
changes between company-wide and peer-group comparisons. */

-- Step 1: Calculate Employee-Level Utilization

SELECT
    employee_id,
    department,
    job_level,
    ROUND(
        SUM(billable_hours) * 100.0 /
        NULLIF(SUM(billable_hours + non_billable_hours), 0),
        2
    ) AS utilization_pct,
    ROUND(
        SUM(recognized_revenue) /
        NULLIF(SUM(billable_hours), 0),
        2
    ) AS revenue_per_billable_hour,
    SUM(recognized_revenue) - SUM(delivery_cost)
        AS contribution_proxy,
    ROUND(
        SUM(rework_hours) * 100.0 /
        NULLIF(SUM(billable_hours + non_billable_hours), 0),
        2
    ) AS rework_rate_pct,
    ROUND(AVG(quality_score), 2) AS avg_quality_score
FROM consulting_delivery_performance
GROUP BY
    employee_id,
    department,
    job_level
ORDER BY employee_id;

-- Step 2: Peer-Group Ranking

WITH employee_metrics AS (
    SELECT
        employee_id,
        department,
        job_level,
        client_tier,
        project_complexity,
        SUM(recognized_revenue) /
            NULLIF(SUM(billable_hours), 0)
            AS revenue_per_billable_hour,
        AVG(quality_score) AS avg_quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        client_tier,
        project_complexity
)
SELECT
    employee_id,
    department,
    job_level,
    client_tier,
    project_complexity,
    ROUND(revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(avg_quality_score, 2)
        AS avg_quality_score,
    RANK() OVER (
        PARTITION BY
            department,
            job_level,
            client_tier,
            project_complexity
        ORDER BY revenue_per_billable_hour DESC
    ) AS revenue_peer_rank,
    RANK() OVER (
        PARTITION BY
            department,
            job_level,
            client_tier,
            project_complexity
        ORDER BY avg_quality_score DESC
    ) AS quality_peer_rank
FROM employee_metrics
ORDER BY
    department,
    job_level,
    revenue_peer_rank;
    
-- Step 3: Top 10% Revenue and Below-Median Quality Employees

WITH employee_metrics AS (
    SELECT
        employee_id,
        department,
        job_level,
        SUM(recognized_revenue) /
            NULLIF(SUM(billable_hours), 0)
            AS revenue_per_billable_hour,
        AVG(quality_score) AS avg_quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level
),
ranked_employees AS (
    SELECT
        *,
        NTILE(10) OVER (
            ORDER BY revenue_per_billable_hour DESC
        ) AS revenue_decile
    FROM employee_metrics
),
quality_median AS (
    SELECT AVG(avg_quality_score) AS median_quality
    FROM (
        SELECT
            avg_quality_score,
            ROW_NUMBER() OVER (
                ORDER BY avg_quality_score
            ) AS rn,
            COUNT(*) OVER () AS total_count
        FROM employee_metrics
    ) q
    WHERE rn IN (
        FLOOR((total_count + 1) / 2),
        FLOOR((total_count + 2) / 2)
    )
)
SELECT
    r.employee_id,
    r.department,
    r.job_level,
    ROUND(r.revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(r.avg_quality_score, 2)
        AS avg_quality_score,
    ROUND(m.median_quality, 2) AS median_quality
FROM ranked_employees r
CROSS JOIN quality_median m
WHERE r.revenue_decile = 1
  AND r.avg_quality_score < m.median_quality
ORDER BY r.revenue_per_billable_hour DESC;

-- Step 4: Compare Company-Wide Rank vs. Peer-Group Rank

WITH employee_metrics AS (
    SELECT
        employee_id,
        department,
        job_level,
        client_tier,
        project_complexity,
        SUM(recognized_revenue) /
            NULLIF(SUM(billable_hours), 0)
            AS revenue_per_billable_hour,
        SUM(billable_hours) * 100.0 /
            NULLIF(
                SUM(billable_hours + non_billable_hours), 0
            ) AS utilization_pct,
        AVG(quality_score) AS quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        client_tier,
        project_complexity
),
ranked_employees AS (
    SELECT
        *,
        RANK() OVER (
            ORDER BY revenue_per_billable_hour DESC
        ) AS company_rank,
        RANK() OVER (
            PARTITION BY
                department,
                job_level,
                client_tier,
                project_complexity
            ORDER BY revenue_per_billable_hour DESC
        ) AS peer_rank
    FROM employee_metrics
)
SELECT
    employee_id,
    department,
    job_level,
    ROUND(revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(utilization_pct, 2) AS utilization_pct,
    ROUND(quality_score, 2) AS quality_score,
    company_rank,
    peer_rank
FROM ranked_employees
ORDER BY employee_id;

-- 2. Performance trajectory and sustained underperformance
/* Identify employees whose quality score declines across at least three consecutive project records. Identify
employees whose revenue per billable hour increases while quality-adjusted productivity declines. Compare
each employee with the cumulative department benchmark available at the time, and flag apparent
improvement driven by changes in complexity or client tier. */

-- Step 1: Identify Consecutive Quality Declines

WITH project_comparison AS (
    SELECT
        employee_id,
        record_id,
        project_start_date,
        quality_score,
        LAG(quality_score) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_quality_score
    FROM consulting_delivery_performance
),
quality_changes AS (
    SELECT
        *,
        CASE
            WHEN quality_score < previous_quality_score THEN 1
            ELSE 0
        END AS is_decline
    FROM project_comparison
),
decline_streaks AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN is_decline = 0 THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS streak_group
    FROM quality_changes
),
streak_counts AS (
    SELECT
        employee_id,
        streak_group,
        COUNT(*) AS consecutive_quality_declines
    FROM decline_streaks
    WHERE is_decline = 1
    GROUP BY employee_id, streak_group
)
SELECT
    employee_id,
    MAX(consecutive_quality_declines)
        AS consecutive_quality_declines
FROM streak_counts
GROUP BY employee_id
HAVING MAX(consecutive_quality_declines) >= 3
ORDER BY consecutive_quality_declines DESC;

-- Step 2: Calculate Employee Project Count and Latest Quality

WITH ranked_projects AS (
    SELECT
        employee_id,
        record_id,
        project_start_date,
        quality_score,
        ROW_NUMBER() OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date DESC, record_id DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY employee_id
        ) AS project_count
    FROM consulting_delivery_performance
)
SELECT
    employee_id,
    MAX(project_count) AS project_count,
    MAX(CASE WHEN rn = 1 THEN quality_score END) AS latest_quality
FROM ranked_projects
GROUP BY employee_id
ORDER BY employee_id;

-- Step 3: Calculate Historical Department Average

SELECT
    employee_id,
    record_id,
    department,
    project_start_date,
    quality_score,
    ROUND(
        AVG(quality_score) OVER (
            PARTITION BY department
            ORDER BY project_start_date, record_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS historical_department_avg
FROM consulting_delivery_performance
ORDER BY employee_id, project_start_date, record_id;

-- Step 4: Calculate Relative Productivity

WITH project_productivity AS (
    SELECT
        employee_id,
        record_id,
        department,
        project_start_date,
        billable_hours,
        recognized_revenue,
        quality_score,
        recognized_revenue / NULLIF(billable_hours, 0)
            AS revenue_per_billable_hour
    FROM consulting_delivery_performance
),
department_benchmark AS (
    SELECT
        *,
        AVG(revenue_per_billable_hour) OVER (
            PARTITION BY department
            ORDER BY project_start_date, record_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS historical_department_revenue_avg
    FROM project_productivity
)
SELECT
    employee_id,
    record_id,
    department,
    project_start_date,
    ROUND(revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(historical_department_revenue_avg, 2)
        AS historical_department_revenue_avg,
    ROUND(
        revenue_per_billable_hour
        - historical_department_revenue_avg,
        2
    ) AS relative_productivity
FROM department_benchmark
ORDER BY employee_id, project_start_date, record_id;

-- Step 5: Performance Trajectory and Sustained Underperformance

WITH project_data AS (
    SELECT
        employee_id,
        record_id,
        project_start_date,
        department,
        billable_hours,
        recognized_revenue,
        quality_score,
        LAG(quality_score) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_quality,
        ROW_NUMBER() OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date DESC, record_id DESC
        ) AS latest_row,
        COUNT(*) OVER (
            PARTITION BY employee_id
        ) AS project_count,
        AVG(quality_score) OVER (
            PARTITION BY department
            ORDER BY project_start_date, record_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS historical_department_avg,
        AVG(
            recognized_revenue / NULLIF(billable_hours, 0)
        ) OVER (
            PARTITION BY department
            ORDER BY project_start_date, record_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS department_revenue_avg
    FROM consulting_delivery_performance
),
decline_flags AS (
    SELECT
        *,
        CASE
            WHEN quality_score < previous_quality THEN 1
            ELSE 0
        END AS is_decline
    FROM project_data
),
streak_groups AS (
    SELECT
        *,
        SUM(
            CASE WHEN is_decline = 0 THEN 1 ELSE 0 END
        ) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS streak_group
    FROM decline_flags
),
streak_counts AS (
    SELECT
        employee_id,
        streak_group,
        COUNT(*) AS decline_count
    FROM streak_groups
    WHERE is_decline = 1
    GROUP BY employee_id, streak_group
),
max_streak AS (
    SELECT
        employee_id,
        MAX(decline_count) AS consecutive_quality_declines
    FROM streak_counts
    GROUP BY employee_id
),
employee_summary AS (
    SELECT
        employee_id,
        MAX(project_count) AS project_count,
        MAX(
            CASE WHEN latest_row = 1 THEN quality_score END
        ) AS latest_quality,
        MAX(
            CASE WHEN latest_row = 1
                 THEN historical_department_avg END
        ) AS historical_department_avg,
        MAX(
            CASE WHEN latest_row = 1 THEN
                recognized_revenue / NULLIF(billable_hours, 0)
                - department_revenue_avg
            END
        ) AS relative_productivity
    FROM project_data
    GROUP BY employee_id
)
SELECT
    e.employee_id,
    e.project_count,
    COALESCE(m.consecutive_quality_declines, 0)
        AS consecutive_quality_declines,
    e.latest_quality,
    ROUND(e.historical_department_avg, 2)
        AS historical_department_avg,
    ROUND(e.relative_productivity, 2)
        AS relative_productivity
FROM employee_summary e
LEFT JOIN max_streak m
    ON e.employee_id = m.employee_id
ORDER BY e.employee_id;

-- Step 6: Compare Consecutive Project Performance

WITH project_comparison AS (
    SELECT
        employee_id,
        record_id,
        project_start_date,
        project_complexity,
        client_tier,
        recognized_revenue,
        billable_hours,
        quality_score,
        recognized_revenue / NULLIF(billable_hours, 0)
            AS revenue_per_billable_hour,
        LAG(
            recognized_revenue / NULLIF(billable_hours, 0)
        ) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_revenue_per_hour,
        LAG(quality_score) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_quality,

        LAG(project_complexity) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_complexity,

        LAG(client_tier) OVER (
            PARTITION BY employee_id
            ORDER BY project_start_date, record_id
        ) AS previous_client_tier
    FROM consulting_delivery_performance
)
SELECT
    employee_id,
    record_id,
    ROUND(previous_revenue_per_hour, 2) AS previous_revenue_per_hour,
    ROUND(revenue_per_billable_hour, 2) AS current_revenue_per_hour,
    previous_quality,
    quality_score AS current_quality,
    CASE
        WHEN revenue_per_billable_hour > previous_revenue_per_hour
         AND revenue_per_billable_hour * quality_score
             < previous_revenue_per_hour * previous_quality
        THEN 'Yes'
        ELSE 'No'
    END AS revenue_up_quality_adjusted_productivity_down,
    CASE
        WHEN project_complexity <> previous_complexity
          OR client_tier <> previous_client_tier
        THEN 'Check complexity/client tier change'
        ELSE 'No change'
    END AS complexity_tier_flag
FROM project_comparison
ORDER BY employee_id, project_start_date, record_id;

-- 3. Counterfactual staffing and resource allocation
/* Identify segments with high delivery costs, elevated rework, and below-median quality. Estimate the
contribution change if 10% of delivery hours were reallocated from bottom-performing segments to segments
with above-median contribution per billable hour. Rank departments and run sensitivity checks excluding
exited employees and projects with fewer than 100 billable hours. */

-- Step 1 — Segment-Level Performance Analysis

SELECT
    department,
    client_tier,
    COUNT(*) AS total_records,
    ROUND(SUM(recognized_revenue), 2)
        AS total_revenue,
    ROUND(SUM(delivery_cost), 2)
        AS total_delivery_cost,
    ROUND(SUM(recognized_revenue - delivery_cost), 2)
        AS contribution_proxy,
    ROUND(
        SUM(recognized_revenue - delivery_cost)
        / NULLIF(SUM(billable_hours), 0),
        2
    ) AS contribution_per_billable_hour,
    ROUND(AVG(rework_hours), 2)
        AS avg_rework_hours,
    ROUND(AVG(quality_score), 2)
        AS avg_quality_score
FROM consulting_delivery_performance
GROUP BY department, client_tier
ORDER BY contribution_per_billable_hour;

-- Step 2: Identify Underperforming Segments

SELECT
    department,
    client_tier,
    ROUND(AVG(delivery_cost), 2) AS avg_delivery_cost,
    ROUND(AVG(rework_hours), 2) AS avg_rework_hours,
    ROUND(AVG(quality_score), 2) AS avg_quality_score,
    ROUND(
        SUM(recognized_revenue - delivery_cost)
        / NULLIF(SUM(billable_hours), 0),
        2
    ) AS contribution_per_billable_hour
FROM consulting_delivery_performance
GROUP BY department, client_tier
ORDER BY
    avg_quality_score ASC,
    avg_rework_hours DESC,
    avg_delivery_cost DESC;
    
-- Step 3: Calculate Median Contribution per Billable Hour

WITH segment_performance AS (
    SELECT
        department,
        client_tier,
        SUM(recognized_revenue - delivery_cost)
            / NULLIF(SUM(billable_hours), 0)
            AS contribution_per_billable_hour
    FROM consulting_delivery_performance
    GROUP BY department, client_tier
),
ranked_segments AS (
    SELECT
        contribution_per_billable_hour,
        ROW_NUMBER() OVER (
            ORDER BY contribution_per_billable_hour
        ) AS rn,
        COUNT(*) OVER () AS total_segments
    FROM segment_performance
    WHERE contribution_per_billable_hour IS NOT NULL
)
SELECT
    ROUND(AVG(contribution_per_billable_hour), 2)
        AS median_contribution_per_billable_hour
FROM ranked_segments
WHERE rn IN (
    FLOOR((total_segments + 1) / 2),
    FLOOR((total_segments + 2) / 2)
);    

-- Step 4: Calculate Contribution After 10% Reallocation

WITH segment_performance AS (
    SELECT
        department,
        client_tier,
        SUM(billable_hours) AS billable_hours,
        SUM(recognized_revenue - delivery_cost) AS contribution,
        SUM(recognized_revenue - delivery_cost)
            / NULLIF(SUM(billable_hours), 0) AS contribution_per_hour
    FROM consulting_delivery_performance
    GROUP BY department, client_tier
),
ranked_segments AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY contribution_per_hour
        ) AS rn,
        COUNT(*) OVER () AS total_segments
    FROM segment_performance
    WHERE contribution_per_hour IS NOT NULL
),
median_value AS (
    SELECT AVG(contribution_per_hour) AS median_rate
    FROM ranked_segments
    WHERE rn IN (
        FLOOR((total_segments + 1) / 2),
        FLOOR((total_segments + 2) / 2)
    )
),
classified AS (
    SELECT
        s.*,
        CASE
            WHEN s.contribution_per_hour < m.median_rate
                THEN 'Donor'
            WHEN s.contribution_per_hour > m.median_rate
                THEN 'Recipient'
            ELSE 'Median'
        END AS segment_group
    FROM segment_performance s
    CROSS JOIN median_value m
),
pool AS (
    SELECT
        SUM(
            CASE WHEN segment_group = 'Donor'
            THEN billable_hours * 0.10 ELSE 0 END
        ) AS donated_hours
    FROM classified
),
recipients AS (
    SELECT SUM(billable_hours) AS recipient_hours
    FROM classified
    WHERE segment_group = 'Recipient'
)
SELECT
    c.department,
    c.client_tier,
    ROUND(c.contribution, 2) AS baseline_contribution,
    ROUND(
        c.contribution
        - CASE
            WHEN c.segment_group = 'Donor'
            THEN c.billable_hours * 0.10 * c.contribution_per_hour
            ELSE 0
          END
        + CASE
            WHEN c.segment_group = 'Recipient'
            THEN p.donated_hours
                 * c.billable_hours
                 / NULLIF(r.recipient_hours, 0)
                 * c.contribution_per_hour
            ELSE 0
          END,
        2
    ) AS contribution_after_reallocation
FROM classified c
CROSS JOIN pool p
CROSS JOIN recipients r
ORDER BY c.department, c.client_tier;

-- Step 5: Department-Level Scenario

WITH segment_performance AS (
    SELECT
        department,
        client_tier,
        SUM(billable_hours) AS billable_hours,
        SUM(recognized_revenue - delivery_cost) AS contribution,
        SUM(recognized_revenue - delivery_cost)
            / NULLIF(SUM(billable_hours), 0) AS contribution_per_hour
    FROM consulting_delivery_performance
    GROUP BY department, client_tier
),
ranked_segments AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY contribution_per_hour
        ) AS rn,
        COUNT(*) OVER () AS total_segments
    FROM segment_performance
    WHERE contribution_per_hour IS NOT NULL
),
median_value AS (
    SELECT AVG(contribution_per_hour) AS median_rate
    FROM ranked_segments
    WHERE rn IN (
        FLOOR((total_segments + 1) / 2),
        FLOOR((total_segments + 2) / 2)
    )
),
classified AS (
    SELECT
        s.*,
        CASE
            WHEN s.contribution_per_hour < m.median_rate
                THEN 'Donor'
            WHEN s.contribution_per_hour > m.median_rate
                THEN 'Recipient'
            ELSE 'Median'
        END AS segment_group
    FROM segment_performance s
    CROSS JOIN median_value m
),
pool AS (
    SELECT
        SUM(
            CASE WHEN segment_group = 'Donor'
            THEN billable_hours * 0.10 ELSE 0 END
        ) AS donated_hours
    FROM classified
),
recipients AS (
    SELECT SUM(billable_hours) AS recipient_hours
    FROM classified
    WHERE segment_group = 'Recipient'
),
scenario AS (
    SELECT
        c.department,
        c.contribution AS baseline_contribution,
        c.contribution
        - CASE
            WHEN c.segment_group = 'Donor'
            THEN c.billable_hours * 0.10 * c.contribution_per_hour
            ELSE 0
          END
        + CASE
            WHEN c.segment_group = 'Recipient'
            THEN p.donated_hours
                 * c.billable_hours
                 / NULLIF(r.recipient_hours, 0)
                 * c.contribution_per_hour
            ELSE 0
          END AS contribution_after_reallocation
    FROM classified c
    CROSS JOIN pool p
    CROSS JOIN recipients r
)
SELECT
    department,
    ROUND(SUM(baseline_contribution), 2)
        AS baseline_contribution,
    ROUND(SUM(contribution_after_reallocation), 2)
        AS contribution_after_reallocation,
    ROUND(
        SUM(contribution_after_reallocation)
        - SUM(baseline_contribution), 2
    ) AS contribution_change,
    ROUND(
        (
            SUM(contribution_after_reallocation)
            - SUM(baseline_contribution)
        ) / NULLIF(SUM(baseline_contribution), 0) * 100,
        2
    ) AS change_pct
FROM scenario
GROUP BY department
ORDER BY contribution_change DESC;

-- Step 6: Sensitivity Analysis

WITH project_hours AS (
    SELECT
        project_id,
        SUM(billable_hours) AS total_project_hours
    FROM consulting_delivery_performance
    GROUP BY project_id
),
scenario_data AS (
    -- Scenario 1: All projects
    SELECT
        'All projects' AS scenario,
        employee_id,
        project_id,
        department,
        client_tier,
        billable_hours,
        recognized_revenue,
        delivery_cost,
        employee_status
    FROM consulting_delivery_performance

    UNION ALL

    -- Scenario 2: Active employees only
    SELECT
        'Active employees only',
        employee_id,
        project_id,
        department,
        client_tier,
        billable_hours,
        recognized_revenue,
        delivery_cost,
        employee_status
    FROM consulting_delivery_performance
    WHERE employee_status <> 'Exited'

    UNION ALL

    -- Scenario 3: Projects with at least 100 billable hours
    SELECT
        'Projects >= 100 billable hours',
        d.employee_id,
        d.project_id,
        d.department,
        d.client_tier,
        d.billable_hours,
        d.recognized_revenue,
        d.delivery_cost,
        d.employee_status
    FROM consulting_delivery_performance d
    JOIN project_hours p
        ON d.project_id = p.project_id
    WHERE p.total_project_hours >= 100
),
scenario_counts AS (
    SELECT
        scenario,
        COUNT(DISTINCT project_id) AS eligible_projects,
        COUNT(DISTINCT employee_id) AS eligible_employees
    FROM scenario_data
    GROUP BY scenario
),
segment_performance AS (
    SELECT
        scenario,
        department,
        client_tier,
        SUM(billable_hours) AS billable_hours,
        SUM(recognized_revenue - delivery_cost) AS contribution,
        SUM(recognized_revenue - delivery_cost)
            / NULLIF(SUM(billable_hours), 0) AS contribution_per_hour
    FROM scenario_data
    GROUP BY scenario, department, client_tier
),
ranked_segments AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY scenario
            ORDER BY contribution_per_hour
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY scenario
        ) AS total_segments
    FROM segment_performance
    WHERE contribution_per_hour IS NOT NULL
),
median_value AS (
    SELECT
        scenario,
        AVG(contribution_per_hour) AS median_rate
    FROM ranked_segments
    WHERE rn IN (
        FLOOR((total_segments + 1) / 2),
        FLOOR((total_segments + 2) / 2)
    )
    GROUP BY scenario
),
classified AS (
    SELECT
        s.*,
        CASE
            WHEN s.contribution_per_hour < m.median_rate
                THEN 'Donor'
            WHEN s.contribution_per_hour > m.median_rate
                THEN 'Recipient'
            ELSE 'Median'
        END AS segment_group
    FROM segment_performance s
    JOIN median_value m
        ON s.scenario = m.scenario
),
reallocation_pool AS (
    SELECT
        scenario,
        SUM(
            CASE
                WHEN segment_group = 'Donor'
                THEN billable_hours * 0.10
                ELSE 0
            END
        ) AS donated_hours,
        SUM(
            CASE
                WHEN segment_group = 'Recipient'
                THEN billable_hours
                ELSE 0
            END
        ) AS recipient_hours
    FROM classified
    GROUP BY scenario
),
scenario_changes AS (
    SELECT
        c.scenario,
        SUM(c.contribution) AS baseline_contribution,
        SUM(
            CASE
                WHEN c.segment_group = 'Donor'
                    THEN -c.billable_hours * 0.10
                         * c.contribution_per_hour
                WHEN c.segment_group = 'Recipient'
                    THEN p.donated_hours
                         * c.billable_hours
                         / NULLIF(p.recipient_hours, 0)
                         * c.contribution_per_hour
                ELSE 0
            END
        ) AS contribution_change
    FROM classified c
    JOIN reallocation_pool p
        ON c.scenario = p.scenario
    GROUP BY c.scenario
)
SELECT
    sc.scenario,
    sc.eligible_projects,
    sc.eligible_employees,
    ROUND(ch.contribution_change, 2) AS contribution_change,
    ROUND(
        ch.contribution_change
        / NULLIF(ch.baseline_contribution, 0) * 100,
        2
    ) AS change_pct
FROM scenario_counts sc
JOIN scenario_changes ch
    ON sc.scenario = ch.scenario
ORDER BY CASE sc.scenario
    WHEN 'All projects' THEN 1
    WHEN 'Active employees only' THEN 2
    WHEN 'Projects >= 100 billable hours' THEN 3
END;

-- 4. Compensation and promotion alignment
/* Identify employees whose productivity and quality remain above peer medians but who have not been
promoted in the last three years. Identify recently promoted employees whose post-promotion quality is below
their job-level median. Compare patterns descriptively across active and exited employees. */

-- Step 1: Calculate Promotion Recency

SELECT DISTINCT
    employee_id,
    department,
    job_level,
    employee_status,
    promotion_date,
    DATEDIFF(CURDATE(), promotion_date)
        AS days_since_promotion,
    CASE
        WHEN promotion_date IS NULL
            THEN 'No Promotion Date'
        WHEN DATEDIFF(CURDATE(), promotion_date) > 1095
            THEN 'Not promoted in 3 years'
        ELSE 'Recently promoted'
    END AS promotion_status
FROM consulting_delivery_performance
ORDER BY employee_id;

-- Step 2: Calculate Employee Relative Productivity

WITH employee_performance AS (
    SELECT
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date,
        SUM(recognized_revenue) AS total_revenue,
        SUM(billable_hours) AS total_billable_hours,
        AVG(quality_score) AS avg_quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date
),
employee_productivity AS (
    SELECT
        *,
        total_revenue / NULLIF(total_billable_hours, 0)
            AS revenue_per_billable_hour
    FROM employee_performance
),
peer_productivity AS (
    SELECT
        department,
        job_level,
        SUM(total_revenue)
            / NULLIF(SUM(total_billable_hours), 0)
            AS peer_revenue_per_billable_hour
    FROM employee_performance
    GROUP BY department, job_level
)
SELECT
    e.employee_id,
    e.department,
    e.job_level,
    e.employee_status,
    ROUND(e.revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(p.peer_revenue_per_billable_hour, 2)
        AS peer_revenue_per_billable_hour,
    ROUND(
        e.revenue_per_billable_hour
        / NULLIF(p.peer_revenue_per_billable_hour, 0),
        2
    ) AS relative_productivity,
    ROUND(e.avg_quality_score, 2) AS avg_quality_score
FROM employee_productivity e
JOIN peer_productivity p
    ON e.department = p.department
   AND e.job_level = p.job_level
ORDER BY e.department, e.job_level, e.employee_id;

-- Step 3: Calculate Peer Medians

WITH employee_performance AS (
    SELECT
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date,
        SUM(recognized_revenue) AS total_revenue,
        SUM(billable_hours) AS total_billable_hours,
        AVG(quality_score) AS avg_quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date
),
employee_productivity AS (
    SELECT
        *,
        total_revenue / NULLIF(total_billable_hours, 0)
            AS revenue_per_billable_hour
    FROM employee_performance
),
peer_productivity AS (
    SELECT
        department,
        job_level,
        SUM(total_revenue)
            / NULLIF(SUM(total_billable_hours), 0)
            AS peer_revenue_per_billable_hour
    FROM employee_performance
    GROUP BY department, job_level
),
employee_relative AS (
    SELECT
        e.*,
        e.revenue_per_billable_hour
            / NULLIF(p.peer_revenue_per_billable_hour, 0)
            AS relative_productivity
    FROM employee_productivity e
    JOIN peer_productivity p
      ON e.department = p.department
     AND e.job_level = p.job_level
),
ranked_peers AS (
    SELECT
        department,
        job_level,
        relative_productivity,
        avg_quality_score,
        ROW_NUMBER() OVER (
            PARTITION BY department, job_level
            ORDER BY relative_productivity
        ) AS productivity_rank,
        ROW_NUMBER() OVER (
            PARTITION BY department, job_level
            ORDER BY avg_quality_score
        ) AS quality_rank,
        COUNT(*) OVER (
            PARTITION BY department, job_level
        ) AS peer_count
    FROM employee_relative
)
SELECT
    department,
    job_level,
    ROUND(AVG(
        CASE
            WHEN productivity_rank IN (
                FLOOR((peer_count + 1) / 2),
                FLOOR((peer_count + 2) / 2)
            )
            THEN relative_productivity
        END
    ), 2) AS median_relative_productivity,
    ROUND(AVG(
        CASE
            WHEN quality_rank IN (
                FLOOR((peer_count + 1) / 2),
                FLOOR((peer_count + 2) / 2)
            )
            THEN avg_quality_score
        END
    ), 2) AS median_quality_score,
    MAX(peer_count) AS employees_in_peer_group
FROM ranked_peers
GROUP BY department, job_level
ORDER BY department, job_level;

-- Step 4: Identify Employees for Promotion Review

WITH employee_performance AS (
    SELECT
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date,
        SUM(recognized_revenue) AS total_revenue,
        SUM(billable_hours) AS total_billable_hours,
        AVG(quality_score) AS quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date
),
employee_productivity AS (
    SELECT
        *,
        total_revenue / NULLIF(total_billable_hours, 0)
            AS revenue_per_billable_hour
    FROM employee_performance
),
peer_productivity AS (
    SELECT
        department,
        job_level,
        SUM(total_revenue)
            / NULLIF(SUM(total_billable_hours), 0)
            AS peer_revenue_per_billable_hour
    FROM employee_performance
    GROUP BY department, job_level
),
employee_relative AS (
    SELECT
        e.*,
        e.revenue_per_billable_hour
            / NULLIF(p.peer_revenue_per_billable_hour, 0)
            AS relative_productivity
    FROM employee_productivity e
    JOIN peer_productivity p
      ON e.department = p.department
     AND e.job_level = p.job_level
),
ranked_peers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY department, job_level
            ORDER BY relative_productivity
        ) AS productivity_rank,
        ROW_NUMBER() OVER (
            PARTITION BY department, job_level
            ORDER BY quality_score
        ) AS quality_rank,
        COUNT(*) OVER (
            PARTITION BY department, job_level
        ) AS peer_count
    FROM employee_relative
),
peer_medians AS (
    SELECT
        department,
        job_level,
        AVG(
            CASE
                WHEN productivity_rank IN (
                    FLOOR((peer_count + 1) / 2),
                    FLOOR((peer_count + 2) / 2)
                )
                THEN relative_productivity
            END
        ) AS median_productivity,
        AVG(
            CASE
                WHEN quality_rank IN (
                    FLOOR((peer_count + 1) / 2),
                    FLOOR((peer_count + 2) / 2)
                )
                THEN quality_score
            END
        ) AS median_quality
    FROM ranked_peers
    GROUP BY department, job_level
)
SELECT
    e.employee_id,
    e.department,
    e.job_level,
    ROUND(e.relative_productivity, 2)
        AS relative_productivity,
    ROUND(e.quality_score, 2) AS quality_score,
    DATEDIFF(CURDATE(), e.promotion_date)
        AS days_since_promotion,
    'Review' AS promotion_review_flag
FROM employee_relative e
JOIN peer_medians m
  ON e.department = m.department
 AND e.job_level = m.job_level
WHERE e.relative_productivity > m.median_productivity
  AND e.quality_score > m.median_quality
  AND (
      e.promotion_date IS NULL
      OR DATEDIFF(CURDATE(), e.promotion_date) > 1095
  )
ORDER BY e.department, e.job_level, e.employee_id;

-- Step 5: Identify Recently Promoted Employees with Low Quality

WITH employee_performance AS (
    SELECT
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date,
        AVG(quality_score) AS quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date
),
ranked_quality AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY job_level
            ORDER BY quality_score
        ) AS quality_rank,
        COUNT(*) OVER (
            PARTITION BY job_level
        ) AS peer_count
    FROM employee_performance
),
job_level_medians AS (
    SELECT
        job_level,
        AVG(
            CASE
                WHEN quality_rank IN (
                    FLOOR((peer_count + 1) / 2),
                    FLOOR((peer_count + 2) / 2)
                )
                THEN quality_score
            END
        ) AS median_quality
    FROM ranked_quality
    GROUP BY job_level
)
SELECT
    e.employee_id,
    e.department,
    e.job_level,
    ROUND(e.quality_score, 2) AS quality_score,
    ROUND(m.median_quality, 2) AS job_level_median_quality,
    DATEDIFF(CURDATE(), e.promotion_date)
        AS days_since_promotion,
    e.employee_status
FROM employee_performance e
JOIN job_level_medians m
    ON e.job_level = m.job_level
WHERE e.promotion_date IS NOT NULL
  AND DATEDIFF(CURDATE(), e.promotion_date) <= 1095
  AND DATEDIFF(CURDATE(), e.promotion_date) >= 0
  AND e.quality_score < m.median_quality
ORDER BY e.job_level, e.quality_score;

-- Step 6: Compare Active and Exited Employees

WITH employee_performance AS (
    SELECT
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date,
        SUM(recognized_revenue) AS total_revenue,
        SUM(billable_hours) AS total_billable_hours,
        AVG(quality_score) AS quality_score
    FROM consulting_delivery_performance
    GROUP BY
        employee_id,
        department,
        job_level,
        employee_status,
        promotion_date
),
employee_productivity AS (
    SELECT
        *,
        total_revenue / NULLIF(total_billable_hours, 0)
            AS revenue_per_billable_hour
    FROM employee_performance
),
peer_productivity AS (
    SELECT
        department,
        job_level,
        SUM(total_revenue)
            / NULLIF(SUM(total_billable_hours), 0)
            AS peer_revenue_per_billable_hour
    FROM employee_performance
    GROUP BY department, job_level
),
employee_relative AS (
    SELECT
        e.*,
        e.revenue_per_billable_hour
            / NULLIF(p.peer_revenue_per_billable_hour, 0)
            AS relative_productivity
    FROM employee_productivity e
    JOIN peer_productivity p
      ON e.department = p.department
     AND e.job_level = p.job_level
)
SELECT
    employee_status,
    COUNT(*) AS employee_count,
    SUM(
        CASE
            WHEN relative_productivity > 1
             AND quality_score > 0
             AND (
                 promotion_date IS NULL
                 OR DATEDIFF(CURDATE(), promotion_date) > 1095
             )
            THEN 1
            ELSE 0
        END
    ) AS high_productivity_not_recently_promoted,
    ROUND(AVG(quality_score), 2) AS average_quality_score,
    ROUND(AVG(relative_productivity), 2)
        AS average_relative_productivity
FROM employee_relative
GROUP BY employee_status
ORDER BY employee_status;

-- 5. Executive decision under uncertainty
/* Prioritize resource-allocation risks, quantify classification changes under alternative peer groups, and
distinguish robust findings from benchmark-sensitive conclusions. */

-- Step 1: Calculate Department Risk Metrics

SELECT
    department,
    COUNT(*) AS total_records,
    ROUND(AVG(quality_score), 2)
        AS average_quality_score,
    ROUND(
        SUM(rework_hours) * 100.0
        / NULLIF(
            SUM(billable_hours + non_billable_hours), 0
        ),
        2
    ) AS rework_rate_pct,
    ROUND(
        SUM(recognized_revenue)
        / NULLIF(SUM(billable_hours), 0),
        2
    ) AS revenue_per_billable_hour,
    ROUND(SUM(delivery_cost), 2)
        AS total_delivery_cost,
    ROUND(
        SUM(recognized_revenue - delivery_cost), 2
    ) AS total_contribution
FROM consulting_delivery_performance
GROUP BY department
ORDER BY total_contribution DESC;

-- Step 2: Identify Department Risk Segments

WITH department_metrics AS (
    SELECT
        department,
        COUNT(*) AS total_records,
        AVG(quality_score) AS average_quality_score,
        SUM(rework_hours) * 100.0
            / NULLIF(
                SUM(billable_hours + non_billable_hours), 0
            ) AS rework_rate_pct,
        SUM(recognized_revenue)
            / NULLIF(SUM(billable_hours), 0)
            AS revenue_per_billable_hour,
        SUM(delivery_cost) AS total_delivery_cost
    FROM consulting_delivery_performance
    GROUP BY department
),
overall_metrics AS (
    SELECT
        AVG(revenue_per_billable_hour)
            AS overall_productivity,
        AVG(total_delivery_cost)
            AS average_delivery_cost
    FROM department_metrics
)
SELECT
    d.department,
    ROUND(d.average_quality_score, 2)
        AS average_quality_score,
    ROUND(d.rework_rate_pct, 2)
        AS rework_rate_pct,
    ROUND(d.revenue_per_billable_hour, 2)
        AS revenue_per_billable_hour,
    ROUND(d.total_delivery_cost, 2)
        AS total_delivery_cost,
    CASE
        WHEN d.rework_rate_pct >= 10
             AND d.average_quality_score < 80
            THEN 'High rework, low quality'
        WHEN d.revenue_per_billable_hour
             < o.overall_productivity
            THEN 'Low relative productivity'
        WHEN d.total_delivery_cost
             > o.average_delivery_cost
            THEN 'High delivery cost'
        ELSE 'No major risk flagged'
    END AS risk_segment
FROM department_metrics d
CROSS JOIN overall_metrics o
ORDER BY d.department;

-- Step 3: Identify Records Affected by Each Risk

WITH record_metrics AS (
    SELECT
        record_id,
        employee_id,
        department,
        job_level,
        billable_hours,
        non_billable_hours,
        recognized_revenue,
        delivery_cost,
        quality_score,
        rework_hours,
        recognized_revenue - delivery_cost AS contribution,
        rework_hours * 100.0
            / NULLIF(billable_hours + non_billable_hours, 0)
            AS rework_rate_pct,
        recognized_revenue
            / NULLIF(billable_hours, 0)
            AS revenue_per_billable_hour
    FROM consulting_delivery_performance
),
department_benchmarks AS (
    SELECT
        department,
        AVG(revenue_per_billable_hour) AS avg_productivity,
        AVG(delivery_cost) AS avg_delivery_cost
    FROM record_metrics
    GROUP BY department
),
risk_records AS (
    SELECT
        r.*,
        CASE
            WHEN r.rework_rate_pct >= 10
                 AND r.quality_score < 80
                THEN 'High rework, low quality'
            WHEN r.revenue_per_billable_hour < b.avg_productivity
                THEN 'Low relative productivity'
            WHEN r.delivery_cost > b.avg_delivery_cost
                THEN 'High delivery cost'
            ELSE 'No major risk flagged'
        END AS risk_segment
    FROM record_metrics r
    JOIN department_benchmarks b
        ON r.department = b.department
)
SELECT
    department,
    risk_segment,
    COUNT(*) AS affected_records,
    ROUND(SUM(contribution), 2)
        AS estimated_contribution_opportunity
FROM risk_records
WHERE risk_segment <> 'No major risk flagged'
GROUP BY department, risk_segment
ORDER BY affected_records DESC;

-- Step 4: Compare Risk Classification Under Alternative Benchmarks

WITH record_metrics AS (
    SELECT
        record_id,
        department,
        billable_hours,
        non_billable_hours,
        recognized_revenue,
        delivery_cost,
        quality_score,
        rework_hours,
        employee_status,
        recognized_revenue - delivery_cost AS contribution,
        rework_hours * 100.0
            / NULLIF(billable_hours + non_billable_hours, 0)
            AS rework_rate_pct,
        recognized_revenue
            / NULLIF(billable_hours, 0)
            AS revenue_per_billable_hour
    FROM consulting_delivery_performance
),
benchmarks AS (
    SELECT
        AVG(revenue_per_billable_hour) AS overall_productivity
    FROM record_metrics
),
comparison AS (
    SELECT
        r.*,
        CASE
            WHEN r.revenue_per_billable_hour < b.overall_productivity
                THEN 'Low relative productivity'
            ELSE 'Other'
        END AS company_benchmark,
        CASE
            WHEN r.revenue_per_billable_hour <
                 (
                     SELECT AVG(r2.revenue_per_billable_hour)
                     FROM record_metrics r2
                     WHERE r2.department = r.department
                 )
                THEN 'Low relative productivity'
            ELSE 'Other'
        END AS department_benchmark
    FROM record_metrics r
    CROSS JOIN benchmarks b
)
SELECT
    department,
    COUNT(*) AS total_records,
    SUM(
        company_benchmark = 'Low relative productivity'
    ) AS company_benchmark_risk_records,
    SUM(
        department_benchmark = 'Low relative productivity'
    ) AS department_benchmark_risk_records,
    SUM(
        company_benchmark <> department_benchmark
    ) AS changed_classifications,
    ROUND(
        SUM(
            CASE
                WHEN company_benchmark <> department_benchmark
                    THEN contribution
                ELSE 0
            END
        ),
        2
    ) AS contribution_in_changed_records
FROM comparison
GROUP BY department
ORDER BY changed_classifications DESC;

-- Step 5: Executive Prioritization Summary

WITH record_metrics AS (
    SELECT
        record_id,
        department,
        billable_hours,
        non_billable_hours,
        recognized_revenue,
        delivery_cost,
        quality_score,
        rework_hours,
        employee_status,
        recognized_revenue - delivery_cost AS contribution,
        rework_hours * 100.0
            / NULLIF(billable_hours + non_billable_hours, 0)
            AS rework_rate_pct,
        recognized_revenue
            / NULLIF(billable_hours, 0)
            AS revenue_per_billable_hour
    FROM consulting_delivery_performance
),
department_metrics AS (
    SELECT
        department,
        AVG(quality_score) AS avg_quality,
        AVG(rework_rate_pct) AS avg_rework_rate,
        AVG(revenue_per_billable_hour) AS avg_productivity,
        AVG(delivery_cost) AS avg_delivery_cost
    FROM record_metrics
    GROUP BY department
),
department_risks AS (
    SELECT
        department,
        CASE
            WHEN avg_rework_rate >= 10 AND avg_quality < 80
                THEN 'High rework, low quality'
            WHEN avg_productivity < (
                SELECT AVG(avg_productivity)
                FROM department_metrics
            )
                THEN 'Low relative productivity'
            WHEN avg_delivery_cost > (
                SELECT AVG(avg_delivery_cost)
                FROM department_metrics
            )
                THEN 'High delivery cost'
            ELSE 'No major risk flagged'
        END AS risk_segment
    FROM department_metrics
),
risk_summary AS (
    SELECT
        r.department,
        d.risk_segment,
        COUNT(*) AS affected_records,
        ROUND(SUM(r.contribution), 2)
            AS estimated_contribution_opportunity
    FROM record_metrics r
    JOIN department_risks d
        ON r.department = d.department
    WHERE d.risk_segment <> 'No major risk flagged'
    GROUP BY r.department, d.risk_segment
),
sensitivity AS (
    SELECT
        department,
        SUM(
            revenue_per_billable_hour < (
                SELECT AVG(revenue_per_billable_hour)
                FROM record_metrics
            )
        ) AS company_risk_records,
        SUM(
            revenue_per_billable_hour < (
                SELECT AVG(r2.revenue_per_billable_hour)
                FROM record_metrics r2
                WHERE r2.department = record_metrics.department
            )
        ) AS department_risk_records
    FROM record_metrics
    GROUP BY department
)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY rs.estimated_contribution_opportunity DESC
    ) AS priority,
    rs.department,
    rs.risk_segment,
    rs.affected_records,
    rs.estimated_contribution_opportunity,
    CASE
        WHEN ABS(s.company_risk_records - s.department_risk_records) = 0
            THEN 'Low'
        WHEN ABS(s.company_risk_records - s.department_risk_records)
             <= 5
            THEN 'Moderate'
        ELSE 'High'
    END AS sensitivity_status
FROM risk_summary rs
JOIN sensitivity s
    ON rs.department = s.department
ORDER BY priority;
