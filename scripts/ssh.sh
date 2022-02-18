#!/bin/bash
if [ -n "$1" ]; then
    EMAIL=$1
else
    EMAIL="example@example.com"
fi
ssh-keygen -t rsa -C $EMAIL -f ~/.ssh/do_id_rsa
