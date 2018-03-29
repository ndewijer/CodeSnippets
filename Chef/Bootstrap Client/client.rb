# See http://docs.chef.io/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
client_key               "#{current_dir}/s-l-b.pem"
chef_server_url          "https://api.chef.io/organizations/s-l-b"
