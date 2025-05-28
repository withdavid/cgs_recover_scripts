#!/bin/bash
#
# Nagios plugin to monitor the number of locks on the system
#

# Nagios return codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Display usage information
usage() {
    echo "Usage: $0 --type=<POSIX|FLOCK> --warning=<warning_threshold> --critical=<critical_threshold>"
    echo
    echo "Options:"
    echo "  --type      Type of lock to monitor (POSIX or FLOCK)"
    echo "  --warning   Warning threshold for number of locks"
    echo "  --critical  Critical threshold for number of locks"
    exit $UNKNOWN
}

# Parse command line options
for i in "$@"; do
    case $i in
        --type=*)
            LOCK_TYPE="${i#*=}"
            ;;
        --warning=*)
            WARNING_THRESHOLD="${i#*=}"
            ;;
        --critical=*)
            CRITICAL_THRESHOLD="${i#*=}"
            ;;
        *)
            usage
            ;;
    esac
done

# Check if all required parameters are provided
if [ -z "$LOCK_TYPE" ] || [ -z "$WARNING_THRESHOLD" ] || [ -z "$CRITICAL_THRESHOLD" ]; then
    echo "UNKNOWN: Missing required parameters"
    usage
fi

# Validate lock type
if [ "$LOCK_TYPE" != "POSIX" ] && [ "$LOCK_TYPE" != "FLOCK" ]; then
    echo "UNKNOWN: Invalid lock type. Must be POSIX or FLOCK"
    exit $UNKNOWN
fi

# Validate thresholds
if ! [[ "$WARNING_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$CRITICAL_THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "UNKNOWN: Thresholds must be positive integers"
    exit $UNKNOWN
fi

# Check if /proc/locks exists
if [ ! -f "/proc/locks" ]; then
    echo "UNKNOWN: /proc/locks file not found"
    exit $UNKNOWN
fi

# Count locks of specified type
LOCK_COUNT=$(grep -c " $LOCK_TYPE " /proc/locks)

# Handle count error
if [ $? -ne 0 ]; then
    echo "UNKNOWN: Error reading /proc/locks"
    exit $UNKNOWN
fi

# Check thresholds and return appropriate status
if [ "$LOCK_COUNT" -ge "$CRITICAL_THRESHOLD" ]; then
    echo "CRITICAL: The system has $LOCK_COUNT $LOCK_TYPE locks, exceeding the critical threshold ($CRITICAL_THRESHOLD)"
    exit $CRITICAL
elif [ "$LOCK_COUNT" -ge "$WARNING_THRESHOLD" ]; then
    echo "WARNING: The system has $LOCK_COUNT $LOCK_TYPE locks, exceeding the warning threshold ($WARNING_THRESHOLD)"
    exit $WARNING
else
    echo "OK: The system has $LOCK_COUNT $LOCK_TYPE locks, which is within the normal range"
    exit $OK
fi 