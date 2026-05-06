# Retention dashboard — week-1 cohort query

The product target from `docs/PHASES.md` is week-1 retention, not engagement
metrics. The PostHog events emitted from the web app are a deliberately small
set. This file documents the queries that turn those events into a single
retention number and a single funnel.

## Events sent (apps/web/src/lib/analytics.tsx)

| name           | properties                              | meaning                                       |
| -------------- | --------------------------------------- | --------------------------------------------- |
| `pageview`     | —                                       | App loaded once.                              |
| `marker_view`  | `experienceId`, `category`              | A marker tap opened the detail sheet.         |
| `sheet_open`   | `experienceId`, `category`              | Alias of `marker_view`, kept for spec parity. |
| `intent_set`   | `length`, `source: "voice" \| "text"`   | User set or changed an intent.                |
| `checkin`      | `experienceId`, `rated: boolean`        | User pressed "I did this".                    |

No PII. DNT honored. PostHog autocapture is **off**.

## Week-1 retention query (PostHog SQL)

```sql
WITH first_seen AS (
  SELECT
    distinct_id,
    MIN(toDate(timestamp)) AS d0
  FROM events
  WHERE event = 'pageview'
  GROUP BY distinct_id
),
return_visit AS (
  SELECT DISTINCT
    e.distinct_id
  FROM events e
  JOIN first_seen f USING (distinct_id)
  WHERE
    e.event = 'pageview'
    AND toDate(e.timestamp) BETWEEN f.d0 + 1 AND f.d0 + 7
)
SELECT
  count(DISTINCT first_seen.distinct_id)            AS cohort_size,
  count(DISTINCT return_visit.distinct_id)          AS retained,
  retained * 1.0 / cohort_size                      AS w1_retention
FROM first_seen
LEFT JOIN return_visit USING (distinct_id);
```

## Funnel: pageview → marker_view → checkin

```sql
SELECT
  countIf(event = 'pageview')     AS pageviews,
  countIf(event = 'marker_view')  AS marker_views,
  countIf(event = 'checkin')      AS checkins
FROM events
WHERE timestamp >= now() - INTERVAL 7 DAY;
```

The funnel is informational, not a target. We do not optimise for "checkin
rate" — that would push the AI ranker toward easy wins instead of honest
recommendations.

## What we deliberately don't track

- IP address, user agent, geolocation precision beyond the existing API call.
- Session recording (disabled in PostHog init).
- Feature-flag exposure events.
- A/B variants — Phase 2 has no live experiments.
