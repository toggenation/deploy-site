# Deploy a site

This script deploys a Wordpress site with the following

* Adds a linux user so php-fpm can run as a user
* Create /var/www/username/ web hosting folder tree
* Set permissions so that other users cannot read them and nginx only has readonly access
* Copies an nginx conf template to /etc/nginx/sites-available/ and configures it to run as the linux user
* Copies a template php-fpm.conf to /etc/php-fpm.d/ and configures it
* Create a logrotate configuration to manage website logs
* uses certbot to create a letsencrypt SSL cert using --nginx plugin
* Create a Maria / MySQL DB and user
* Downloads and unpacks to the web root the latest wordpress
* Modifies the Wordpress wp-config.php with:
	* Database user details
	* wp-config security salts
 * Echos DB and WP credentials to console to take a copy of

## Requires

* pwgen
* certbot with nginx plugin
* envsubst



## How to use

```sh
cp env.example .env
# make it more secure
chmod 600 .env
```

Edit `.env` and add the linux user and website domain

```sh
SITE_NAME="My Test Wordpress Site"

# new user name linux
NEW_USER=linuxuser

# domain name
NEW_DOMAIN=exampledomain.com.au

MYSQL_PWD="MySuperSecretMariaDbRootPasswordHere" # mysql root password here
```

Run the script 

```sh
./deploy-site.sh
```

To remove the DB, directories and conf and start again (does NOT remove Let's Encrypt certificates)
```sh
./deploy-site.sh remove
```
