#!/bin/bash
# =========================================================================== #
# Description:        Rsync the production website to the staging server/website.
# Details:            Rsync Pull, the script will run from the staging server.
# Made for:           Linux, Cloudpanel (Debian & Ubuntu).
# Requirements:       ssh-keygen - ssh-copy-id root@127.0.0.1 (replace IP)
# Author:             WP Speed Expert
# Author URI:         https://wpspeedexpert.com
# Version:            0.7
# Make executable:    chmod +x rsync-pull-production-to-staging.sh
# Crontab @weekly:    0 0 * * MON /home/{PATH}/rsync-pull-production-to-staging.sh > /home/{PATH}/rsync-pull-production-to-staging.log 2>&1
# =========================================================================== #
#
# Variables
PRODUCTION_URL=("production.domain.com")
STAGING_URL=("staging.domain.com")
#
PRODUCTION_DATABASE=("production-database")
STAGING_DATABASE=("staging-database")
TABLE_PREFIX=("wp_")
#
PRODUCTION_SERVER_SSH=("root@0.0.0.0")
#
PRODUCTION_PATH=("/home/website/htdocs/production.domain.com")
STAGING_PATH=("/home/staging/htdocs/staging.domain.com")
#
STAGING_SCRIPT_PATH=("/home/staging")
PRODUCTION_SCRIPT_PATH=("/home/production")
#
STAGING_USER_GROUP=("user-staging")
#
CURRENT_DATE_TIME=$(date +"%Y-%m-%d %T")
#
# Log the date and time
echo "[+] NOTICE: Start script: ${CURRENT_DATE_TIME}"

# Check for WP directory & wp-config.php
if [ ! -d ${STAGING_PATH} ]; then
  echo "[+] ERROR: Directory ${STAGING_PATH} does not exist"
  echo ""
  exit
fi
if [ ! -f ${STAGING_PATH}/wp-config.php ]; then
  echo "[+] ERROR: No wp-config.php in ${STAGING_PATH}"
  echo ""
fi
  echo "[+] SUCCESS: Found wp-config.php in ${STAGING_PATH}"

# Stop nginx
# echo "[+] NOTICE: Stop Nginx."
# sudo systemctl stop nginx

# Clean and remove website files (except for the uploads directory & exceptions)
# find ${STAGING_PATH}/ -mindepth 1 ! -regex '^'${STAGING_PATH}'/wp-config.php' ! -regex '^'${STAGING_PATH}'/wp-content/uploads\(/.*\)?' -delete
#
# Clean and remove destination website files (except for the wp-config.php)
find ${STAGING_PATH}/ -mindepth 1 ! -regex '^'${STAGING_PATH}'/wp-config.php' -delete
#

# Export the remote MySQL database |  ${PRODUCTION_PATH}
echo "[+] NOTICE: Export the remote database: ${PRODUCTION_DATABASE}"
# Use Cloudpanel CLI
ssh ${PRODUCTION_SERVER_SSH} "clpctl db:export --databaseName=${PRODUCTION_DATABASE} --file=${PRODUCTION_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz"
# Use mysqldump
# ssh ${PRODUCTION_SERVER_SSH} "mysqldump --defaults-extra-file=${STAGING_SCRIPT_PATH}/production.cnf -D ${PRODUCTION_DATABASE} | gzip > ${PRODUCTION_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz"
echo "[+] NOTICE: Synching the database: ${PRODUCTION_DATABASE}.sql.gz"
rsync -azP ${PRODUCTION_SERVER_SSH}:${PRODUCTION_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz ${STAGING_SCRIPT_PATH}/tmp

# Cleanup remote database export file
echo "[+] NOTICE: Clean up the remote database export file: ${PRODUCTION_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz"
ssh ${PRODUCTION_SERVER_SSH} "rm ${PRODUCTION_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz"

# Drop all database tables (clean up)
echo "[+] NOTICE: Drop all database tables ..."
#
# Create a variable with the command to list all tables
tables=$(mysql --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf -Nse 'SHOW TABLES' ${STAGING_DATABASE})
#
# Loop through the tables and drop each one
for table in $tables; do
    echo "[+] NOTICE: Dropping $table from ${STAGING_DATABASE} ..."
    mysql --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf  -e "DROP TABLE $table" ${STAGING_DATABASE}
done
    echo "[+] SUCCESS: All tables dropped from ${STAGING_DATABASE}."

# Import the MySQL database:
echo "[+] NOTICE: Import the MySQL database: ${STAGING_DATABASE} ..."
# Use Cloudpanel CLI
clpctl db:import --databaseName=${STAGING_DATABASE} --file=${STAGING_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz
# Use mysqldump
# mysqldump --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf -D ${STAGING_DATABASE} < ${STAGING_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz
echo "[+] NOTICE: Clean up the database export file: ${STAGING_DATABASE} ..."
rm ${STAGING_SCRIPT_PATH}/tmp/${PRODUCTION_DATABASE}.sql.gz

# Search and replace URL in the database
echo "[+] NOTICE: Search and replace URL in the database: ${STAGING_DATABASE} ..."
mysql --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf -D ${STAGING_DATABASE} -e "
UPDATE ${TABLE_PREFIX}options SET option_value = REPLACE (option_value, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}') WHERE option_name = 'home' OR option_name = 'siteurl';
UPDATE ${TABLE_PREFIX}posts SET post_content = REPLACE (post_content, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}posts SET post_excerpt = REPLACE (post_excerpt, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}postmeta SET meta_value = REPLACE (meta_value, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}termmeta SET meta_value = REPLACE (meta_value, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}comments SET comment_content = REPLACE (comment_content, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}comments SET comment_author_url = REPLACE (comment_author_url, 'https://${PRODUCTION_URL}','https://${STAGING_URL}');
UPDATE ${TABLE_PREFIX}posts SET guid = REPLACE (guid, 'https://${PRODUCTION_URL}', 'https://${STAGING_URL}') WHERE post_type = 'attachment';
"

# Enable: Discourage search engines from indexing this website
echo "[+] NOTICE: Enable discourage search engines from indexing this website."
mysql --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf -D ${STAGING_DATABASE} -e "
UPDATE ${TABLE_PREFIX}options SET option_value = replace (option_value, '1', '0') WHERE option_name = 'blog_public';
"

# Check if query was_successful
echo "[+] NOTICE: Check if query was_successful."
query=$(mysql --defaults-extra-file=${STAGING_SCRIPT_PATH}/my.cnf -D ${STAGING_DATABASE} -se "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name = 'siteurl';")
echo "[+] SUCCESS: Siteurl = $query."

# Rsync website files (pull)
echo "[+] NOTICE: Start Rsync pull"
rsync -azP --update --delete --no-perms --no-owner --no-group --no-times --exclude 'wp-content/cache/*' --exclude 'wp-content/backups-dup-pro/*' --exclude 'wp-config.php' ${PRODUCTION_SERVER_SSH}:${PRODUCTION_PATH}/ ${STAGING_PATH}

# Set correct ownership
echo "[+] NOTICE: Set correct ownership."
chown -Rf ${STAGING_USER_GROUP}:${STAGING_USER_GROUP} ${STAGING_PATH}

# Set correct file permissions for folders
echo "[+] NOTICE: Set correct file permissions for folders."
chmod 00755 -R ${STAGING_PATH}

# Set correct file permissions for files
echo "[+] NOTICE: Set correct file permissions for files."
find ${STAGING_PATH}/ -type f -print0 | xargs -0 chmod 00644

# Flush & restart Redis
echo "[+] NOTICE: Flush & restart Redis."
redis-cli FLUSHALL
sudo systemctl restart redis-server

# Start nginx
# echo "[+] NOTICE: Start Nginx."
# sudo systemctl stop nginx

# End of the script
echo "[+] NOTICE: End of script: ${CURRENT_DATE_TIME}"
exit
