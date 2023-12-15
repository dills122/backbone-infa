#!/bin/bash

domain="dsteele.dev"
umami_sub_domain="umami"
ssl_email="dylansteele57@gmail.com"

# Need to update the naming to the url of site ex. umami.dsteele.dev
sudo rm -rf /etc/nginx/conf.d/* && sudo rm -rf /etc/nginx/sites-available/*
# Copy Nginx config files
sudo cp ~/backbone-src/.docker/nginx/conf.d/prod/* /etc/nginx/sites-available/

sudo nginx -t

sudo certbot --nginx --non-interactive --agree-tos --redirect -d ${umami_sub_domain}.${domain} -d www.${umami_sub_domain}.${domain} -m ${ssl_email}
