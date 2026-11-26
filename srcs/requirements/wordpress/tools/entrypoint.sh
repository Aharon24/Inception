#!/bin/sh

set -eu

WP_PATH="/var/www/html"
WP_SOURCE="/usr/src/wordpress"

DB_PASSWORD_FILE="/run/secrets/db_password"
WP_ADMIN_PASSWORD_FILE="/run/secrets/wp_admin_password"

# Check required environment variables
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"
: "${WORDPRESS_URL:?WORDPRESS_URL is not set}"
: "${WORDPRESS_TITLE:?WORDPRESS_TITLE is not set}"
: "${WORDPRESS_ADMIN_USER:?WORDPRESS_ADMIN_USER is not set}"
: "${WORDPRESS_ADMIN_EMAIL:?WORDPRESS_ADMIN_EMAIL is not set}"

MYSQL_HOST="${MYSQL_HOST:-mariadb}"
export MYSQL_HOST

# Check required Docker secrets
if [ ! -s "$DB_PASSWORD_FILE" ]; then
    echo "ERROR: Database password secret is missing" >&2
    exit 1
fi

if [ ! -s "$WP_ADMIN_PASSWORD_FILE" ]; then
    echo "ERROR: WordPress admin password secret is missing" >&2
    exit 1
fi

# Wait until MariaDB accepts connections
echo "Waiting for MariaDB..."

i=0

until php -r '
mysqli_report(MYSQLI_REPORT_OFF);

$host = getenv("MYSQL_HOST");
$database = getenv("MYSQL_DATABASE");
$user = getenv("MYSQL_USER");
$password = trim(file_get_contents("/run/secrets/db_password"));

$conn = new mysqli($host, $user, $password, $database, 3306);

if ($conn->connect_errno) {
    exit(1);
}

$result = $conn->query("SELECT 1");
$conn->close();

if (!$result) {
    exit(1);
}
' >/dev/null 2>&1
do
    i=$((i + 1))

    if [ "$i" -ge 60 ]; then
        echo "ERROR: MariaDB did not become ready in 60 seconds" >&2
        exit 1
    fi

    sleep 1
done

echo "MariaDB is ready."

# Prepare WordPress files
mkdir -p "$WP_PATH"

if [ ! -f "$WP_PATH/wp-load.php" ]; then
    echo "Copying WordPress files..."
    cp -a "$WP_SOURCE/." "$WP_PATH/"
fi

# Create wp-config.php if missing
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo "Creating wp-config.php..."

    wp --allow-root --path="$WP_PATH" config create \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbhost="$MYSQL_HOST:3306" \
        --dbprefix=wp_ \
        --skip-check \
        --prompt=dbpass < "$DB_PASSWORD_FILE"
fi

# Install WordPress only on first initialization
if wp --allow-root --path="$WP_PATH" core is-installed >/dev/null 2>&1; then
    echo "WordPress is already installed. Skipping installation."
else
    echo "Installing WordPress..."

    wp --allow-root --path="$WP_PATH" core install \
        --url="$WORDPRESS_URL" \
        --title="$WORDPRESS_TITLE" \
        --admin_user="$WORDPRESS_ADMIN_USER" \
        --admin_email="$WORDPRESS_ADMIN_EMAIL" \
        --skip-email \
        --prompt=admin_password < "$WP_ADMIN_PASSWORD_FILE"
fi

# Set permissions
chown -R www-data:www-data "$WP_PATH"

# Prepare PHP-FPM runtime directory
mkdir -p /run/php

# Start PHP-FPM in foreground
echo "Starting PHP-FPM..."

exec php-fpm8.2 --nodaemonize
