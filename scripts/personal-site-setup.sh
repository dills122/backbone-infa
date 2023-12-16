#!/bin/bash

remote_path="/var/www/html/dsteele.dev"

/usr/bin/git clone https://github.com/dills122/dsteele.dev.git

pushd dsteele.dev

mkdir $remote_path

/usr/bin/bash build-deploy.sh $remote_path

/usr/bin/bash certbot.sh dsteele.dev

popd

sudo systemctl restart nginx
