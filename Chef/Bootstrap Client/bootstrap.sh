#!/bin/bash -xev

# Do some chef pre-work
sudo /bin/mkdir -p /etc/chef
sudo /bin/mkdir -p /var/lib/chef
sudo /bin/mkdir -p /var/log/chef

sudo mv ~/s-l-b.pem /etc/chef/s-l-b.pem
sudo mv ~/first-boot.json /etc/chef/first-boot.json


# Install chef
sudo curl -L https://omnitruck.chef.io/install.sh | sudo bash || error_exit 'could not install chef'

NODE_NAME=node-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)

# Create client.rb
/bin/echo 'log_location     STDOUT' >> ~/client.rb
/bin/echo -e "chef_server_url  \"https://api.chef.io/organizations/s-l-b\"" >> ~/client.rb
/bin/echo -e "validation_client_name \"s-l-b-validator\"" >> ~/client.rb
/bin/echo -e "validation_key \"/etc/chef/s-l-b.pem\"" >> ~/client.rb
/bin/echo -e "node_name  \"${NODE_NAME}\"" >> ~/client.rb

sudo mv ~/client.rb /etc/chef/client.rb

sudo chef-client -j /etc/chef/first-boot.json
