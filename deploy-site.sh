#!/bin/bash


. ./.env

echo New linux user: $NEW_USER
echo New site: $NEW_DOMAIN

if [ -z "$MYSQL_ROOT_PASS" ];
then
	echo You need specify MYSQL_ROOT_PASS="<PasswordHere>" in .env
	exit
fi

function createUser {

	echo Creating user "$1"

	useradd -c "created `date +'%Y-%m-%d'`" -m "$1"

	mkdir -p $WWW_DIR/{tmp,uploads,web}
	echo -e "This file needs to be here to enable\nnightly backup do not delete" > $WWW_DIR/backup

	chown -Rv $1:$1 $WWW_DIR

}

function removeAll {

	echo "Removing All"

	[ -f $NEW_NGINX_CONF ] && (
		echo Removing $NEW_NGINX_CONF
		rm -rf $NEW_NGINX_CONF
		systemctl restart nginx
	)
	[ -f $NEW_PHPFPM_CONF ] && (
		echo Removing $NEW_PHPFPM_CONF
		rm -rf $NEW_PHPFPM_CONF
		systemctl restart $PHPFPM_SERVICE
	)

	id $1 > /dev/null 2>&1 && userdel -r $1
	[ -d $WWW_DIR/web ] && ( 
		echo Removing $WWW_DIR
		rm -rf $WWW_DIR
	)

	echo Deleting DB
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

mysql -uroot -p$MYSQL_ROOT_PASS <<MYSQL_SCRIPT
DROP DATABASE $MYSQL_DB;
DROP USER '$MYSQL_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo "MySQL user deleted"
echo "MySQL DB Deleted"
echo "Username:   $MYSQL_USER"


}

function createDB {
	
echo Creating DB

mysql -uroot -p$MYSQL_ROOT_PASS <<MYSQL_SCRIPT
CREATE DATABASE $MYSQL_DB;
CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASS';
GRANT ALL PRIVILEGES ON $MYSQL_DB.* TO '$MYSQL_USER'@'localhost';
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
		
		echo User does not exist ok to continue
	else 
		echo User $1 exists. Exiting...
		exit 1
	fi
}

function createPhpFpmConf {
	echo Creating php-fpm conf
	sed $PHPFPM_CONF_TEMPLATE -e "s/${NEW_USER_TAG}/$NEW_USER/g" > $NEW_PHPFPM_CONF	
}

function createNginxConf {
	echo Creating nginx conf	
	sed $NGINX_CONF_TEMPLATE -e "s/${NEW_DOMAIN_TAG}/$NEW_DOMAIN/g" -e "s/${NEW_USER_TAG}/$NEW_USER/g" > $NEW_NGINX_CONF

	ln -sf $NEW_NGINX_CONF $SITES_ENABLED/
}

function createConfFiles {
	createPhpFpmConf
	createNginxConf
}


function deployWordpress {

wget -qO- $WORDPRESS_LATEST | tar -zx --strip-components=1 -C $WWW_DIR/web > /dev/null 2>&1

cp $WP_CONFIG_SAMPLE $WP_CONFIG_TMP
sed -i "s/^define.*DB_NAME.*$/define('DB_NAME', '$MYSQL_DB');/" $WP_CONFIG_TMP
sed -i "s/^define.*DB_USER.*$/define('DB_USER', '$MYSQL_USER');/" $WP_CONFIG_TMP
sed -i "s/^define.*DB_PASSWORD.*$/define('DB_PASSWORD', '$MYSQL_PASS');/" $WP_CONFIG_TMP

SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
cat $WP_CONFIG_TMP | sed "/AUTH_KEY/,/NONCE_SALT/c $(echo $SALTS)" | sed 's/;\sdefine/;\ndefine/g' > $WP_CONFIG
rm $WP_CONFIG_TMP 

}
function reloadServices {

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

function changeOwner {

	chown -R $NEW_USER:$NEW_USER $WWW_DIR

}


if [ ! -d /etc/letsencrypt/live/$NEW_DOMAIN ];
then
	getCert
fi

if [ "$1" = "remove" ];
then
	echo Removing all
	removeAll $NEW_USER
fi
createDB
#sleep 5
# deleteDB $NEW_USER
checkUser $NEW_USER
createUser $NEW_USER
checkFile $NEW_NGINX_CONF
checkFile $NEW_PHPFPM_CONF


createConfFiles
deployWordpress
deployTheme
deployChildTheme
changeOwner
reloadServices

