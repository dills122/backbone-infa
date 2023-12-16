#!/bin/bash
EMAILDEFAULT="dylansteele57@gmail.com"
EMAIL="${1:-$EMAILDEFAULT}"

ssh-keygen -t ed25519 -C $EMAIL -f ~/.ssh/do_id_ed25519
