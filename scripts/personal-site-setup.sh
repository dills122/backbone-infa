#!/bin/bash

/usr/bin/git clone https://github.com/dills122/dsteele.dev.git

pushd dsteele.dev

docker-compose up "build"

mkdir /var/html/dsteele.dev

cp ./_site/* /var/html/dsteele.dev

/usr/bin/bash certbot.sh dsteele.dev

popd

sudo systemctl restart nginx
