#!/bin/bash

/usr/bin/bash certbot.sh dsteele.dev umami

git clone https://github.com/mikecao/umami.git

pushd umami

sudo npm i -g yarn
yarn install
# yarn build

echo "DATABASE_URL=postgresql://main:Ba21tedao23094!@localhost:5432/mydb" >.env

docker pull ghcr.io/mikecao/umami:postgresql-latest
docker compose up -d

popd
