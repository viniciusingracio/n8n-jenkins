SELECT
  COUNT(distinct unique_name) AS value,
  TO_CHAR(TO_TIMESTAMP(join_time / 1000)::timestamp, 'YYYY-MM') AS date
FROM
  users
GROUP BY date
