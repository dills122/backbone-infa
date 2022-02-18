# Backbone Infrastructure

This repo contains all the scripts & configs necessary to build & deploy all backbone services needed for my web applications

## Infrastructure for Application

DO Slugs: https://slugs.do-api.dev/

### Getting Started

You will need to have `terraform` installed to start.

Env Vars you need to ensure are set so that `terraform` can work.

```bash
TF_VAR_do_token='Digitial_Ocean_token'
TF_VAR_ssh_key_fingerprint='ssh fingerprint in DO console'
```

```bash
# downloads provider and sets up the dir
terraform init

# creates a plan based off the configuration setup
terraform plan -out droplet.tfplan

# execute the created plan and deploy
terraform apply "droplet.tfplan"

# clean up
terraform destroy
```

Then once its finished you should be able to navigate to the ip address listed in the console.

#### SSH

A script is included that you can use to setup your SSH key, you can call it like:

```bash
sh ssh.sh email@email.com
```

SSH into the newly created droplet with your new SSH key

```bash
ssh root@IP_ADDRESS -i ~/.ssh/do_id_rsa.pub
```

#### Certbot Info

https://www.nginx.com/blog/using-free-ssltls-certificates-from-lets-encrypt-with-nginx/
