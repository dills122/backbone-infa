#!/bin/bash

DOMAINDEFAULT="dsteele.dev"
domain="${1:-$DOMAINDEFAULT}"
sub_domain="$2"
ssl_email="dylansteele57@gmail.com"

generateSSL() {
    local full_domain=$1
    local to_base_path="/etc/nginx/"
    local file_name="$full_domain.conf"
    # Copy Nginx config files
    sudo cp ~/backbone-src/.docker/nginx/conf.d/prod/${file_name} ${to_base_path}sites-available/
    # symlink confs from sites-available to sites-enabled
    sudo ln -s ${to_base_path}sites-available/${file_name} ${to_base_path}sites-enabled/

    sudo nginx -t

    sudo certbot --nginx --non-interactive --agree-tos --redirect -d ${full_domain} -d www.${full_domain} -m ${ssl_email}
}

if [ -n "$sub_domain" ]; then
    generateSSL "$sub_domain.$domain"
else
    generateSSL "$domain"
fi
