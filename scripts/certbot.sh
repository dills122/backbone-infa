#!/bin/bash

domain= $1 || "dsteele.dev"
sub_domain= $2
ssl_email="dylansteele57@gmail.com"

# Copy Nginx config files
sudo cp ~/backbone-src/.docker/nginx/conf.d/prod/* /etc/nginx/sites-available/

sudo nginx -t

if [ -n "$sub_domain" ]; then
    sudo certbot --nginx --non-interactive --agree-tos --redirect -d ${sub_domain}.${domain} -d www.${sub_domain}.${domain} -m ${ssl_email}
else
    sudo certbot --nginx --non-interactive --agree-tos --redirect -d ${domain} -d www.${domain} -m ${ssl_email}
fi
