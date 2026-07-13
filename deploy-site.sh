#!/bin/bash

. ./.env

echo Linux user: $NEW_USER
echo Domain: $NEW_DOMAIN
echo Site name: $SITE_NAME
echo WP Table Prefix: $WP_TABLE_PREFIX

if [ -z "$MYSQL_PWD" ];
then
	echo You need to specify the MYSQL_PWD="<PasswordHere>" in .env
	exit
fi

function createWebRoot {
	echo Creating $WWW_DIR and sub folders
	mkdir -p $WWW_DIR/{tmp,uploads,web,log}
	echo -e "This file needs to be here to enable\nnightly backup do not delete" > $WWW_DIR/backup
}

function createLogFiles {
    echo Create empty log files
    [ -d "$WWW_DIR/log" ] && touch $WWW_DIR/log/{access,error,access_php-fpm,error_php-fpm,slow_php-fpm}.log
}

function createUser {
	echo Creating user "$1" and site dir
	useradd -c "created `date +'%Y-%m-%d'`" -m "$1"
    echo Add nginx user www-data to "$1" group to allow nginx to read user dir
    usermod -a -G "$1" www-data
}

function removeUser {
    echo Remove user "$1"
	id $1 > /dev/null 2>&1 && userdel -r $1
    groupdel -f "$1"
}

function removeNginxConf {
	[ -f $NEW_NGINX_CONF ] && (
		echo Removing $NEW_NGINX_CONF
		rm -f $NEW_NGINX_CONF
	        rm -f $NEW_NGINX_CONF $SITES_ENABLED/$NEW_USER.conf
		systemctl restart nginx
	)
}

function removeLogRotateConf {
	[ -f $NEW_LOGROTATE_CONF ] && (
		echo Removing $NEW_LOGROTATE_CONF
		rm -f $NEW_LOGROTATE_CONF

		systemctl restart logrotate.timer
	)
}

function removePhpFpmConf {
		[ -f $NEW_PHPFPM_CONF ] && (
		echo Removing $NEW_PHPFPM_CONF
		rm -rf $NEW_PHPFPM_CONF
		systemctl restart $PHPFPM_SERVICE
	)
}

function removeSiteDir {
    echo Remove "$WWW_DIR" web root
    [ -d $WWW_DIR/web ] && ( 
		echo Removing $WWW_DIR
		rm -rf $WWW_DIR
	)
}

function removeAll {
	echo "Removing All"
	removeNginxConf
	removePhpFpmConf
	removeLogRotateConf
	removeUser "$1"
	removeSiteDir 
	deleteDB

	echo End of remove all. exiting
	exit 0
}	

function checkFile {
	echo Check for $1
	if [ -f "$1" ]
	then
		echo File found exiting...
		exit 1
	else 
		echo File $1 not found continuing...
	fi
}

function deleteDB {
	echo "Deleting DB"

	MYSQL_PWD="$MYSQL_PWD" mysql -uroot <<-MYSQL_SCRIPT
	DROP DATABASE $MYSQL_DB;
	DROP USER '$MYSQL_USER'@'$DB_HOST';
	FLUSH PRIVILEGES;
	MYSQL_SCRIPT
    
	echo "MySQL user deleted"
	echo "MySQL DB Deleted"
	echo "Username:   $MYSQL_USER"
}

function checkDbAndUser {
	echo Checking for pre existing DB user and DB

	DB_EXISTS=`MYSQL_PWD="$MYSQL_PWD" mysql -u root -sse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$MYSQL_DB'"`

	DB_USER_EXISTS=`MYSQL_PWD="$MYSQL_PWD" mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = '$MYSQL_USER' AND Host = '$DB_HOST')"`

	[ "$DB_EXISTS" == "1" ] && echo DB Exists: $MYSQL_DB
	[ "$DB_USER_EXISTS" == "1" ] && echo DB User Exists: \'$MYSQL_USER\'@\'$DB_HOST\'

	if [ "$DB_USER_EXISTS" == "1" -o "$DB_EXISTS" == "1" ];
	then
		echo Cannot deploy site with a pre-existing DB or DB User. 
		echo Please run \`$(basename -- "$0") remove\` or edit \`.env\`
		echo Exiting...
		exit 1;
	fi
}
	
function createDB {
	echo Creating DB

	MYSQL_PWD="$MYSQL_PWD" mysql -uroot <<-MYSQL_SCRIPT
	CREATE DATABASE $MYSQL_DB 
  		CHARACTER SET utf8mb4
    	COLLATE utf8mb4_unicode_520_ci;

	CREATE USER '$MYSQL_USER'@'$DB_HOST' IDENTIFIED BY '$MYSQL_PASS';

	GRANT ALL PRIVILEGES ON $MYSQL_DB.* TO '$MYSQL_USER'@'$DB_HOST';

	FLUSH PRIVILEGES;
	MYSQL_SCRIPT

	echo "MySQL user created."
	echo "Username:   $MYSQL_USER"
	echo "Password:   $MYSQL_PASS"
}

function getCert {
	echo Get Lets Encrypt Cert
	certbot certonly -d $NEW_DOMAIN -d www.$NEW_DOMAIN --nginx
}

function checkUser {
	echo Check for user: $1

	id $1 > /dev/null 2>&1
	
	if [ $? -eq 1 ] 
	then
		echo User "$1" does not exist ok to continue
	else 
		echo User $1 exists. Exiting...
		exit 1
	fi
}

function createLogRotateConf {
	echo Creating $NEW_LOGROTATE_CONF
	envsubst '$NEW_USER $PHP_VERSION' < $LOGROTATE_CONF_TEMPLATE > $NEW_LOGROTATE_CONF
}

function createPhpFpmConf {
    echo Creating php-fpm conf for $NEW_USER
    envsubst '$NEW_USER' < "$PHPFPM_CONF_TEMPLATE" > "$NEW_PHPFPM_CONF"
}

function createNginxConf {
    echo Creating nginx conf for $NEW_USER	
    envsubst '$NEW_USER $NEW_DOMAIN' < "$NGINX_CONF_TEMPLATE" > "$NEW_NGINX_CONF"

    ln -sf $NEW_NGINX_CONF $SITES_ENABLED/
}

function createConfFiles {
	createPhpFpmConf
	createNginxConf
	createLogRotateConf
}

function deployWordpress {
	sudo -u $NEW_USER wp core download --path=$WWW_DIR/web

	sudo -u $NEW_USER wp config create --path=$WWW_DIR/web \
		--dbname=$MYSQL_DB \
		--dbuser=$MYSQL_USER \
		--dbpass=$MYSQL_PASS \
		--dbprefix=$WP_TABLE_PREFIX

	sudo -u $NEW_USER wp core install --path=$WWW_DIR/web \
		 --url=$SITE_URL \
		 --title="$SITE_NAME" \
		 --admin_user=$WP_ADMIN_USER \
 		 --admin_email=$WP_ADMIN_EMAIL

	echo WP Admin User: $WP_ADMIN_USER
	echo WP Admin Email: $WP_ADMIN_EMAIL
}

function reloadServices {
	echo Restarting services
	systemctl reload nginx
	systemctl reload $PHPFPM_SERVICE
}

function deployTheme {
	unzip -d $THEME_DIR $THEME > /dev/null 2>&1
}

function deployChildTheme {
	mkdir $CHILD_THEME_DIR
	chown $NEW_USER:$NEW_USER $CHILD_THEME_DIR

cat > $CHILD_THEME_DIR/style.css << ENDOFSTYLES
/*
 Theme Name:     Divi Child
 Theme URI:      https://www.elegantthemes.com/gallery/divi/
 Description:    Divi Child Theme
 Author:         Elegant Themes
 Author URI:     https://www.elegantthemes.com
 Template:       Divi
 Version:        1.0.0
*/
 
 
/* =Theme customization starts here
------------------------------------------------------- */
ENDOFSTYLES

cat > $CHILD_THEME_DIR/functions.php << ENDOFFUNCTIONS
<?php
function my_theme_enqueue_styles() { 
    wp_enqueue_style( 'parent-style', get_template_directory_uri() . '/style.css' );
}
add_action( 'wp_enqueue_scripts', 'my_theme_enqueue_styles' );

ENDOFFUNCTIONS
}

function setPermsOnSiteDirs {
    echo Set perms on "$WWW_DIR"
    if [ -z "$WWW_DIR" ];
    then
        echo Directory variable WWW_DIR empty. Exiting...
        exit 1
    fi

    if [ ! -d "$WWW_DIR/web" ];
    then 
        echo Directory $WWW_DIR/web missing cannot set ownershipe and perms...
        exit 1
    fi

	chown -R $NEW_USER:$NEW_USER "$WWW_DIR"

    # drwxr_x___
    # frw_r_____

    find "$WWW_DIR" -type d -exec chmod 750 {} \;
    find "$WWW_DIR" -type f -exec chmod 640 {} \;
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    echo "Please run with: sudo $0" >&2
    exit 1
fi

if [ ! -d /etc/letsencrypt/live/$NEW_DOMAIN ];
then
       	getCert
fi

if [ "$1" = "remove" ];
then
	echo Removing all
	removeAll $NEW_USER
fi

checkDbAndUser

createDB

checkUser $NEW_USER

createUser $NEW_USER

createWebRoot $NEW_USER

createLogFiles $NEW_USER

checkFile $NEW_NGINX_CONF

checkFile $NEW_PHPFPM_CONF

createConfFiles

setPermsOnSiteDirs

deployWordpress

# don't use this now
# deployTheme
# deployChildTheme

reloadServices

