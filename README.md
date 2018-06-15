# terraform-aws-chef-solo-provision
terraform script to interact with AWS, generate a load balancer and servers under it, ensure service uptime with different time zones and create_before_destroy terraform flag

Module stack supporting multiple deployment scenarios of an Auto Scaling Group
to an AWS VPC.

## Prerequisites

* curl
* ssh
* ssh-keygen
* internet connection, open to AWS APIs :)

## Requirements

* Terraform 0.8.0 or newer
* AWS provider

## How to run

(First time you download the repo, you'll have to run "terraform init")

* Usage: ./run <terraform_operation> <aws_access_key> <aws_secret_key> <server_count>

* e.g(terraform apply):    ./run apply <aws_access_key> <aws_secret_key> 2
* e.g(terraform destroy):	./run destroy <aws_access_key> <aws_secret_key> 2


## Notes

* 3 different subnets are defined in aws_servers.tf, if we want to create more than 3 servers this bit must be modified to support it.
* The repository includes a dummy java app  into the chef directory that gets deployed in provisioning time with the instance and the chef-solo code.
* No downtime should happen when adding or removing instances, although to improve provisioning timings the app should be externalized (eg. a Nexus server or the image itself). The downtime is avoided by the terraform flag create_before_destroy and the provisioning health_check.sh that checks the java app is running before the instance gets tagged as created.
* WARNING - Running the script with 3 servers and then running it again with 2 will trigger a current terraform bug: https://github.com/hashicorp/terraform/issues/18261


