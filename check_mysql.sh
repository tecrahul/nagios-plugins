#!/bin/bash

# ==============================================================================
# Script Name: MySQL Comprehensive Monitoring Script
# Author: Rahul Kumar
# Version: 1.0.2
# Copyright: Copyright (c) tecadmin.net
# Description:
#   This script provides comprehensive monitoring capabilities for MySQL servers,
#   supporting authentication via command-line parameters or the `.my.cnf` file.
#   It enables checking of connection usage, slow queries, deadlocks, sleeping
#   processes, and execution times. Users can specify metrics to monitor and set
#   custom thresholds through command-line arguments. This script can be integrated
#   with Nagios or similar monitoring tools for automated MySQL health checks and
#   performance monitoring.
# Usage:
#   ./mysql_monitoring.sh [options]
#   Options:
#     --user [username]                         MySQL user (optional if using .my.cnf)
#     --password [password]                     MySQL password (optional if using .my.cnf)
#     --host [host]                             MySQL host
#     --port [port]                             MySQL port
#     --check-connections                       Enable checking of MySQL connections
#     --check-slow-queries                      Enable checking of slow queries
#     --check-deadlocks                         Enable checking for deadlocks
#     --check-sleeping-processes                Enable checking of sleeping processes
#     --check-execution-time                    Enable checking of execution time
#     --connections-threshold [percentage]      Threshold for connections usage
#     --slow-queries-threshold [number]         Threshold for slow queries
#     --sleeping-processes-threshold [number]   Threshold for sleeping processes
#     --execution-time-threshold [seconds]      Threshold for execution time
# ==============================================================================

# Default settings (can be overridden by command-line arguments)
MYSQL_USER=""
MYSQL_PASS=""
MYSQL_HOST="localhost"
MYSQL_PORT=3306
CHECK_CONNECTIONS="no"
CHECK_SLOW_QUERIES="no"
CHECK_DEADLOCKS="no"
CHECK_SLEEPING_PROCESSES="no"
CHECK_EXECUTION_TIME="no"
MAX_CONNECTIONS_PERCENTAGE_THRESHOLD=75
SLOW_QUERIES_THRESHOLD=100
MAX_SLEEPING_PROCESSES=10
MAX_EXECUTION_TIME=300 # in seconds

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user) MYSQL_USER="$2"; shift ;;
        --password) MYSQL_PASS="$2"; shift ;;
        --host) MYSQL_HOST="$2"; shift ;;
		--port) MYSQL_PORT="$2"; shift ;;
        --check-connections) CHECK_CONNECTIONS="yes" ;;
        --check-slow-queries) CHECK_SLOW_QUERIES="yes" ;;
        --check-deadlocks) CHECK_DEADLOCKS="yes" ;;
        --check-sleeping-processes) CHECK_SLEEPING_PROCESSES="yes" ;;
        --check-execution-time) CHECK_EXECUTION_TIME="yes" ;;
        --connections-threshold) MAX_CONNECTIONS_PERCENTAGE_THRESHOLD="$2"; shift ;;
        --slow-queries-threshold) SLOW_QUERIES_THRESHOLD="$2"; shift ;;
        --sleeping-processes-threshold) MAX_SLEEPING_PROCESSES="$2"; shift ;;
        --execution-time-threshold) MAX_EXECUTION_TIME="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Authentication setup
if [[ -n "$MYSQL_USER" && -n "$MYSQL_PASS" ]]; then
    AUTH_USER="-u $MYSQL_USER"
	AUTH_PASS="MYSQL_PWD=$MYSQL_PASS"
else
    AUTHENTICATION="" # Rely on .my.cnf for authentication
fi

# Check MySQL connection
"$AUTH_PASS" mysql $AUTH_USER -h "$MYSQL_HOST" -p $MYSQL_PORT -e "SELECT 1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "CRITICAL: Cannot connect to MySQL."
    exit 2
fi

OVERALL_STATUS="OK"
CONSOLIDATED_MESSAGES=""

# Function to check each monitoring aspect
perform_check() {
    local check_type="$1"
    local status="OK" # Default status for each check
    local message=""  # Message for each check
    case "$check_type" in
        connections)
            if [ "$CHECK_CONNECTIONS" == "yes" ]; then
                local total_connections=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW VARIABLES LIKE 'max_connections';" | grep 'max_connections' | awk '{print $2}')
                local current_connections=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW STATUS LIKE 'Threads_connected';" | grep 'Threads_connected' | awk '{print $2}')
                local usage_percentage=$(awk "BEGIN {printf \"%.2f\", ({current_connections}/${total_connections})*100}")
                if (( $(echo "$usage_percentage > $MAX_CONNECTIONS_PERCENTAGE_THRESHOLD" | bc -l) )); then
                    status="WARNING"
                    OVERALL_STATUS="WARNING"
                fi
                message="CONNECTIONS:${current_connections}:${status}"
            fi
            ;;
        slow_queries)
            if [ "$CHECK_SLOW_QUERIES" == "yes" ]; then
                local slow_queries=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" | grep 'Slow_queries' | awk '{print $2}')
                if [ "$slow_queries" -gt "$SLOW_QUERIES_THRESHOLD" ]; then
                    status="WARNING"
                    OVERALL_STATUS="WARNING"
                fi
                message="SLOW_QUERIES:${slow_queries}:${status}"
            fi
            ;;
        deadlocks)
            if [ "$CHECK_DEADLOCKS" == "yes" ]; then
                local deadlocks=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW ENGINE INNODB STATUS\G" | grep -c "LATEST DETECTED DEADLOCK")
                if [ "$deadlocks" -gt 0 ]; then
                    status="CRITICAL"
                    OVERALL_STATUS="CRITICAL"
                fi
                message="DEADLOCKS:${deadlocks}:${status}"
            fi
            ;;
        sleeping_processes)
            if [ "$CHECK_SLEEPING_PROCESSES" == "yes" ]; then
                local sleeping_processes=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW PROCESSLIST" | grep -c Sleep)
                if [ "$sleeping_processes" -gt "$MAX_SLEEPING_PROCESSES" ]; then
                    status="WARNING"
                    OVERALL_STATUS="WARNING"
                fi
                message="SLEEPING_PROCESSES:${sleeping_processes}:${status}"
            fi
            ;;
        execution_time)
            if [ "$CHECK_EXECUTION_TIME" == "yes" ]; then
                local max_time=$("$AUTH_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$AUTH_USER" -e "SHOW PROCESSLIST" | awk '{print $6}' | grep -v Time | sort -nr | head -n 1)
                if [ "$max_time" -gt "$MAX_EXECUTION_TIME" ]; then
                    status="WARNING"
                    OVERALL_STATUS="WARNING"
                fi
                message="EXECUTION_TIME:${max_time}sec:${status}"
            fi
            ;;
    esac
	
	# Append the message for this check to the consolidated messages string, with a comma if not the first message
    if [ -n "$CONSOLIDATED_MESSAGES" ]; then
        CONSOLIDATED_MESSAGES+=", "
    fi
    CONSOLIDATED_MESSAGES+="$message"
}

# Perform checks based on command-line arguments
[ "$CHECK_CONNECTIONS" == "yes" ] && perform_check connections
[ "$CHECK_SLOW_QUERIES" == "yes" ] && perform_check slow_queries
[ "$CHECK_DEADLOCKS" == "yes" ] && perform_check deadlocks
[ "$CHECK_SLEEPING_PROCESSES" == "yes" ] && perform_check sleeping_processes
[ "$CHECK_EXECUTION_TIME" == "yes" ] && perform_check execution_time

# Output final result
echo "$OVERALL_STATUS: $CONSOLIDATED_MESSAGES"

# Modify exit status based on OVERALL_STATUS
if [ "$OVERALL_STATUS" == "CRITICAL" ]; then
    exit 2
elif [ "$OVERALL_STATUS" == "WARNING" ]; then
    exit 1
else
    exit 0
fi
