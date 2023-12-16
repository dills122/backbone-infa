#!/bin/bash

domain="$1" || "dsteele.dev"
sub_domain="$2"
ssl_email="dylansteele57@gmail.com"

generateSSL() {
    local full_domain=$1
    # Copy Nginx config files
    sudo cp ~/backbone-src/.docker/nginx/conf.d/prod/${full_domain} /etc/nginx/sites-available/

    sudo nginx -t

    sudo certbot --nginx --non-interactive --agree-tos --redirect -d ${full_domain} -d www.${full_domain} -m ${ssl_email}
}

if [ -n "$sub_domain" ]; then
    generateSSL "$sub_domain.$domain"
else
    generateSSL "$domain"
fi
