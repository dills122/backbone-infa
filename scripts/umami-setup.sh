#!/bin/bash

git clone https://github.com/mikecao/umami.git

pushd umami

npm i
npm run build

docker pull ghcr.io/mikecao/umami:postgresql-latest
docker-compose up -d

popd
