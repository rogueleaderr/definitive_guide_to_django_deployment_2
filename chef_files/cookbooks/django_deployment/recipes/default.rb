#
# Cookbook Name:: django
# Recipe:: default
#
# Copyright 2013, George London
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

#code derived in part from http://ericholscher.com/blog/2010/nov/9/building-django-app-server-chef-part-2/
#code derived in part from https://github.com/Yipit/djangoquickstart-cookbook/blob/master/recipes/default.rb

# Calculate some locations based on set attributes

node.default["env_name"] = "#{node.app_name}-env"
node.default["project_home"] = "#{node.env_root}/#{node.env_name}"
node.default["app_home"] = "#{node.project_home}/#{node.app_name}"

execute "Update apt repos" do
    command "apt-get update"
end

include_recipe 'python'
include_recipe 'git'

node.base_packages.each do |pkg|
    package pkg do
        :upgrade
    end
end

template "/home/ubuntu/.bashrc" do
  source "bashrc.erb"
  mode 0644
  owner "ubuntu"
  group "ubuntu"
  variables(
    :role => node.name,
    :prompt_color => node.prompt_color)
end

node.pip_python_packages.each do |pkg|
    execute "install-#{pkg}" do
        command "pip install #{pkg}"
        not_if "[ `pip freeze | grep #{pkg} ]"
    end
end

# Create the project folder, create a virtualenv
# clone the project repo, install requirements
# To see exactly what this does, checkout providers/build_repo.rb
# This only runs if the project home directory doesn't exist yet
django_deployment_build_repo node.branch do
  action :add
  settings node.settings
  repo node.repo
  app_name node.app_name
  env_root node.env_root
  not_if { File.directory? node.project_home }
end

# Ubuntu distribution supervisor is old, but it starts automatically which is helpful
package "supervisor" do
    action :install
end

# Set up a command to update supervisor on config
# changes, but don't actually do anything now
execute "supervisor update" do
  command "sudo supervisorctl reread && sudo supervisorctl update"
  action :nothing
end

# Set up configuration files inside your app repo for supervisor, gunicorn, and nginx

template "#{node.app_home}/conf/supervisor/#{node.app_name}.conf" do
  source "site_supervisor.conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.project_home,
    :app_home => node.app_home)
  notifies :run, resources(:execute => "supervisor update")
end

template "#{node.app_home}/conf/gunicorn/#{node.app_name}.conf" do
  source "gunicorn.production.conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.project_home,
    :app_home => node.app_home)
  notifies :run, resources(:execute => "supervisor update")
end

template "#{node.app_home}/scripts/go_production_gunicorn.sh" do
  source "go_production_gunicorn.sh.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.project_home,
    :app_home => node.app_home)
  notifies :run, resources(:execute => "supervisor update")
end

# Set up nginx sites-enables and retsart on changes

template "/etc/nginx/sites-enabled/default" do
  source "nginx-default.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_home => node.project_home)
  notifies :restart, "service[nginx]"
end

service 'nginx' do
  supports :restart => true, :reload => true
  action :enable
end

# symlink conf files into system locations

template "/etc/supervisor/conf.d/#{node.app_name}.conf" do end

# Set up gunicorn through supervisor and restart on changes

template "/etc/supervisor/conf.d/gunicorn.conf" do
  source "gunicorn.conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.project_home,
    :settings => "#{node.app_home}/settings/__init__.py",
    :conf => "#{node.app_home}/conf/gunicorn/gunicorn.conf")
  notifies :run, resources(:execute => "supervisor update")
end


=begin
execute "install-reqs" do
  command "source /home/ubuntu/sites/hello_world/
  && pip install -r /home/ubuntu/sites/hello_world/requirements.txt"
  action :run
  user "ubuntu"
end
=end
