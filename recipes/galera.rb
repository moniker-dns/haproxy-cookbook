#
# Cookbook Name:: haproxy
# Recipe:: galera
#
# recipe to support dropping haproxy infront of a Galera MySQL cluster
# http://www.mysqlperformanceblog.com/2012/06/20/percona-xtradb-cluster-reference-architecture-with-haproxy/
#
# Copyright 2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

pool_members = search("node", "role:#{node['haproxy']['app_server_role']} AND chef_environment:#{node.chef_environment}") || []

# load balancer may be in the pool
pool_members << node if node.run_list.roles.include?(node['haproxy']['app_server_role'])


# we prefer connecting via the private ip if 
# pool members are in the same region/az
pool_members.map! do |member|
  server_ip = begin
    # meta_data is supplied by dnsaas::meta_data
    if member.attribute?('meta_data') && member['meta_data'].attribute?('region')
      if node.attribute?('meta_data') && (member['meta_data']['region'] == node['meta_data']['region']) && !member['meta_data']['region'].nil?
        member['meta_data']['private_ipv4']
      else
        member['meta_data']['public_ipv4']
      end
    else
      member['ipaddress']
    end
  end
  {:ipaddress => server_ip, :hostname => member['hostname']}
end

package "haproxy" do
  action :install
end

cookbook_file "/etc/default/haproxy" do
  source "haproxy-default"
  owner "root"
  group "root"
  mode 00644
  notifies :restart, "service[haproxy]", :immediately
end

template "/etc/haproxy/haproxy.cfg" do
  source "haproxy-galera.cfg.erb"
  owner "root"
  group "root"
  mode 00644
  variables(
    :pool_members => pool_members.uniq,
    :defaults_options => defaults_options,
    :defaults_timeouts => defaults_timeouts
  )
  notifies :reload, "service[haproxy]", :immediately
end

service "haproxy" do
  supports :restart => true, :status => true, :reload => true
  action [:enable, :start]
end
