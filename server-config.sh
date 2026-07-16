#!/bin/bash

groupdel -f hosting
userdel -r site1

groupadd hosting
useradd -m -g hosting -k /dev/null site1

# apt update
# apt dist-upgrade -y

apt install nginx -y

usermod -aG hosting www-data
usermod -aG hosting ja

apt install zip unzip curl php-fpm php php-cli php-{zip,bz2,curl,mbstring,intl,xml,sqlite3,mysql} -y

apt install mariadb-server

apt install pwgen logrotate

curl -s -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
curl -s -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.asc
curl -s -L https://raw.githubusercontent.com/wp-cli/builds/gh-pages/wp-cli.pgp | gpg --import
gpg --verify wp-cli.phar.asc wp-cli.phar 2>&1 | grep -q 'Good signature'

if [ "$?" == "0" ]; 
then
	echo Good sig
	chmod +x wp-cli.phar
	mv wp-cli.phar /usr/local/bin/wp
else 
	echo Bad sig
	exit 1
fi

