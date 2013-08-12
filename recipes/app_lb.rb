#
# Cookbook Name:: haproxy
# Recipe:: app_lb
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
Chef::Log.info "haproxy::app_lb about to search.. role:#{node['haproxy']['app_server_role']} AND chef_environment:#{node.chef_environment}"
pool_members = search("node", "role:#{node['haproxy']['app_server_role']} AND chef_environment:#{node.chef_environment}") || []
Chef::Log.info "haproxy::app_lb found #{pool_members.count()} pool members"

# load balancer may be in the pool
pool_members << node if node.run_list.roles.include?(node['haproxy']['app_server_role'])

Chef::Log.info "haproxy::app_lb found #{pool_members.count()} pool members"

# we prefer connecting via local_ipv4 if
# pool members are in the same cloud
# TODO refactor this logic into library...see COOK-494
pool_members.map! do |member|
  Chef::Log.info "haproxy::app_lb in the map...#{node['hostname']}"
  server_ip = begin
    if member.attribute?('meta_data')
      Chef::Log.info "we #{node['hostname']} are in #{node['meta_data']['region']}"
      Chef::Log.info "potential pool member #{member['hostname']} is in #{member['meta_data']['region']}"
      if node.attribute?('meta_data') && (member['meta_data']['region'] == node['meta_data']['region'])
        Chef::Log.info "using private_ipv4 #{member['meta_data']['private_ipv4']} for the pool_member"
        member['meta_data']['private_ipv4']
      else
        Chef::Log.info "using public_ipv4 #{member['meta_data']['public_ipv4']} for the pool_member"
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
  notifies :restart, "service[haproxy]"
end

template "/etc/haproxy/haproxy.cfg" do
  source "haproxy-app_lb.cfg.erb"
  owner "root"
  group "root"
  mode 00644
  variables(
    :pool_members => pool_members.uniq,
    :defaults_options => defaults_options,
    :defaults_timeouts => defaults_timeouts
  )
  notifies :reload, "service[haproxy]"
end

service "haproxy" do
  supports :restart => true, :status => true, :reload => true
  action [:enable, :start]
end
