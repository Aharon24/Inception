#!/bin/sh

set -e

DATADIR="/var/lib/mysql"

# Create required directories
mkdir -p /run/mysqld "$DATADIR"

# Give MariaDB permissions to access its files
chown -R mysql:mysql /run/mysqld "$DATADIR"

# Initialize database system tables on first start
if [ ! -d "$DATADIR/mysql" ]; then
    echo "Initializing MariaDB..."

    mariadb-install-db \
        --user=mysql \
        --datadir="$DATADIR" \
        --skip-test-db
fi

# Start MariaDB in the foreground
exec mariadbd --user=mysql --console