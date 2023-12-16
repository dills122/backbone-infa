#!/bin/bash

remote_path="/var/www/html/dsteele.dev"

/usr/bin/git clone https://github.com/dills122/dsteele.dev.git

cd ./dsteele.dev

git pull

mkdir $remote_path

/usr/bin/bash build-deploy.sh $remote_path

/usr/bin/bash ~/backbone-src/scripts/certbot.sh dsteele.dev

cd ..

sudo systemctl restart nginx
