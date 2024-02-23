#!/bin/bash

# ==============================================================================
# SCRIPT: check_memory.sh
# AUTHOR: Rahul Kumar
# COPYRIGHT: tecadmin.net
# Version: 1.0.1
# DESCRIPTION:
#   This script is designed to monitor and report on system memory usage. It
#   allows for warning and critical thresholds to be set for memory usage
#   percentages, providing alerts based on the specified criteria. The script
#   supports output in different units (Bytes, Kilobytes, Megabytes, Gigabytes)
#   for flexible monitoring requirements. This utility is particularly useful
#   for system administrators and monitoring tools like Nagios to keep an eye
#   on system health and perform proactive maintenance.
# 
# USAGE:
#   ./check_memory.sh [ -w <warning_threshold> ] [ -c <critical_threshold> ] [ -u <unit> ]
#   -w, --warning=INTEGER[%]   Warning threshold as a percentage of used memory.
#   -c, --critical=INTEGER[%]  Critical threshold as a percentage of used memory.
#   -u, --unit=UNIT            Unit to use for output (b, K, M, G). Default: M
# 
# EXAMPLES:
#   ./check_memory.sh -w 80 -c 90 -u M
#   This command sets a warning threshold at 80% memory usage and a critical
#   threshold at 90%, with output in Megabytes.
# ==============================================================================


# Set binary location an defaul values
FREECMD='/usr/bin/free'
UNIT='M' # Default unit
WARNING_THRESHOLD=80
CRITICAL_THRESHOLD=90

# Function to show usage
usage() {
  echo "Usage: $0 [ -w <warning_threshold> ] [ -c <critical_threshold> ] [ -u <unit> ]"
  echo "   -w, --warning=INTEGER[%]   Warning threshold as a percentage of used memory."
  echo "   -c, --critical=INTEGER[%]  Critical threshold as a percentage of used memory."
  echo "   -u, --unit=UNIT            Unit to use for output (b, K, M, G). Default: $UNIT"
  exit 3
}

# Parse command line options
while getopts ":w:c:u:" opt; do
  case $opt in
    w) WARNING_THRESHOLD="$OPTARG" ;;
    c) CRITICAL_THRESHOLD="$OPTARG" ;;
    u) UNIT="$OPTARG" ;;
    \?) usage ;;
  esac
done

# Function to convert memory to the specified unit
convert_memory() {
  local memory=$1
  case $UNIT in
    b) echo $memory ;;
    K) echo $((memory / 1024)) ;;
    M) echo $((memory / 1024 / 1024)) ;;
    G) echo $((memory / 1024 / 1024 / 1024)) ;;
    *) echo "Error: Unknown unit $UNIT. Must be one of 'b', 'K', 'M', 'G'."; exit 3 ;;
  esac
}

# Extract memory data
total_bytes=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')
free_bytes=$(grep MemFree /proc/meminfo | awk '{print $2 * 1024}')
buffers_bytes=$(grep Buffers /proc/meminfo | awk '{print $2 * 1024}')
cached_bytes=$(grep "^Cached" /proc/meminfo | awk '{print $2 * 1024}')
available_bytes=$((free_bytes + buffers_bytes + cached_bytes))

# Convert to specified unit
total=$(convert_memory $total_bytes)
available=$(convert_memory $available_bytes)

# Calculate used memory
used=$(convert_memory $((total_bytes - available_bytes)))

# Calculate usage percentage
usage_percentage=$((100 - (available * 100 / total)))

# Compare usage against thresholds
if [ "$usage_percentage" -ge "$CRITICAL_THRESHOLD" ]; then
  echo "CRITICAL: Memory usage is above critical threshold ($CRITICAL_THRESHOLD%). $used$UNIT used ($usage_percentage% of total)."
  exit 2
elif [ "$usage_percentage" -ge "$WARNING_THRESHOLD" ]; then
  echo "WARNING: Memory usage is above warning threshold ($WARNING_THRESHOLD%). $used$UNIT used ($usage_percentage% of total)."
  exit 1
else
  echo "OK: Memory usage is within bounds. $used$UNIT used ($usage_percentage% of total)."
  exit 0
fi
