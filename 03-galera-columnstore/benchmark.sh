mkdir -p "$HOME/gigavolt-evidence"

(
set -eu

echo "USE gigavolt_benchmark;"
echo "SET SESSION profiling_history_size=100;"
echo "SET SESSION profiling=0;"

for round in 0 1 2 3 4 5; do
    if (( round % 2 == 0 )); then
        engines="innodb columnstore"
    else
        engines="columnstore innodb"
    fi

    for engine in $engines; do
        if [[ "$engine" == "innodb" ]]; then
            echo "SET SESSION columnstore_select_handler=OFF;"
        else
            echo "SET SESSION columnstore_select_handler=ON;"
        fi

        echo "SELECT SQL_NO_CACHE
            service_type,
            COUNT(*) AS row_count,
            SUM(hours_spent) AS total_hours,
            SUM(labor_cost) AS total_cost,
            ROUND(AVG(labor_cost), 2) AS average_cost
        FROM analytics_${engine}
        GROUP BY service_type
        ORDER BY service_type;"
    done

    if (( round == 0 )); then
        echo "SET SESSION profiling=1;"
    fi
done

echo "SHOW PROFILES;"
) > "$HOME/gigavolt-evidence/benchmark.sql"
sudo mariadb --table < "$HOME/gigavolt-evidence/benchmark.sql" \
  2>&1 | tee "$HOME/gigavolt-evidence/benchmark-results.txt"
