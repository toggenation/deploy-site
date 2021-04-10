# Deploy a site

This script deploys a Wordpress site with the following

* Adds a linux user so php-fpm can run as a user
* Create /var/www/username/ folder tree and sets perms to the created linux user
* Copies an nginx conf template to /etc/nginx/conf.d and modifies it
* Copies a template php-fpm.conf to /etc/php-fpm.d/ and modifies it
* uses certbot to create a letsencrypt SSL cert using --nginx plugin
* Adds the Divi theme to wordpress
* Create a Divi Child Theme
* Create a MySQL DB and user
* Downloads and unpacks to the web root the latest wordpress
* Modifies the Wordpress wp-config.php with:
	* Database user details
	* wp-config security salts

## Requires

pwgen
certbot with nginx plugin



## How to use

```sh
cp env.example env
```

Edit env and add the linux user and website domain

```sh
# new user name linux
NEW_USER=exuser

# domain name
NEW_DOMAIN=exampledomain.com.au
```

Run the script 

```sh
export MYSQL_ROOT_PASS=MySuperSecretMySQLRootPassord
./deploy-site.sh
```

To remove the DB, directories and conf and start again

```sh
./deploy-site.sh remove
```
