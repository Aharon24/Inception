#!/bin/sh

set -e
umask 077

DATADIR="/var/lib/mysql"
RUN_DIR="/run/mysqld"
INIT_SOCKET="$RUN_DIR/mariadb-init.sock"
INIT_MARKER="$DATADIR/.inception_initialized"
ROOT_CLIENT_CNF="$RUN_DIR/root-client.cnf"

DB_PASSWORD_FILE="/run/secrets/db_password"
ROOT_PASSWORD_FILE="/run/secrets/db_root_password"

# Check required environment variables
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"

# Allow only simple SQL identifiers
case "$MYSQL_DATABASE" in
    ''|*[!a-zA-Z0-9_]*)
        echo "ERROR: Invalid MYSQL_DATABASE" >&2
        exit 1
        ;;
esac

case "$MYSQL_USER" in
    ''|*[!a-zA-Z0-9_]*)
        echo "ERROR: Invalid MYSQL_USER" >&2
        exit 1
        ;;
esac

# Read passwords from Docker secrets
[ -s "$DB_PASSWORD_FILE" ] || {
    echo "ERROR: DB password secret is missing" >&2
    exit 1
}

[ -s "$ROOT_PASSWORD_FILE" ] || {
    echo "ERROR: Root password secret is missing" >&2
    exit 1
}

DB_PASSWORD=$(cat "$DB_PASSWORD_FILE")
ROOT_PASSWORD=$(cat "$ROOT_PASSWORD_FILE")

# Create required directories
mkdir -p "$RUN_DIR" "$DATADIR"

# Give MariaDB permissions
chown -R mysql:mysql "$RUN_DIR" "$DATADIR"

# Initialize system tables on first start
if [ ! -d "$DATADIR/mysql" ]; then
    echo "Initializing MariaDB..."

    mariadb-install-db \
        --user=mysql \
        --datadir="$DATADIR" \
        --skip-test-db
fi

# Configure database and users only once
if [ ! -f "$INIT_MARKER" ]; then
    echo "Configuring MariaDB..."

    # Start temporary MariaDB server
    mariadbd \
        --user=mysql \
        --datadir="$DATADIR" \
        --skip-networking \
        --socket="$INIT_SOCKET" \
        --pid-file="$RUN_DIR/mariadb-init.pid" \
        --console &

    MYSQLD_PID=$!

    # Wait until temporary server is ready
    i=0
    until mariadb-admin \
        --protocol=socket \
        --socket="$INIT_SOCKET" \
        --user=root ping --silent >/dev/null 2>&1
    do
        i=$((i + 1))

        if [ "$i" -ge 30 ]; then
            echo "ERROR: MariaDB initialization server did not start" >&2
            kill "$MYSQLD_PID" 2>/dev/null || true
            wait "$MYSQLD_PID" 2>/dev/null || true
            exit 1
        fi

        sleep 1
    done

    # Create database, user and permissions
    mariadb \
        --protocol=socket \
        --socket="$INIT_SOCKET" \
        --user=root <<SQL
CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\`;

CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';

ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';

GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';

ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';

FLUSH PRIVILEGES;
SQL

    # Remember successful configuration
    touch "$INIT_MARKER"
    chown mysql:mysql "$INIT_MARKER"

    # Create temporary secure client configuration
    cat > "$ROOT_CLIENT_CNF" <<EOF
[client]
user=root
password=$ROOT_PASSWORD
protocol=socket
socket=$INIT_SOCKET
EOF

    chmod 600 "$ROOT_CLIENT_CNF"

    # Stop temporary MariaDB server
    mariadb-admin \
        --defaults-extra-file="$ROOT_CLIENT_CNF" \
        shutdown

    rm -f "$ROOT_CLIENT_CNF"

    wait "$MYSQLD_PID" || true

    echo "MariaDB configuration completed."
fi

# Start the main MariaDB server
echo "Starting MariaDB..."

exec mariadbd --user=mysql --console