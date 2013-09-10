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
node.default["env_home"] = "#{node.project_root}/#{node.env_name}"
node.default["app_home"] = "#{node.project_root}/#{node.app_name}"

=begin
execute "Update apt repos" do
    command "apt-get update"
end
=end

# make sure python and git are installed, because we'll need them
depends 'python'
depends 'git'
depends "application"
depends "application_python"

node.base_packages.each do |pkg|
    package pkg do
        :upgrade
    end
end

# setup a nice bash shell configuration
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

application "#{app_name}" do
  path "/srv/#{app_name}"
  owner "nobody"
  group "nogroup"
  repository "https://github.com/#{repo}.git"
  revision "master"
  migrate true

  django do
    requirements "requirements/requirements.txt"
    settings_template "settings.py.erb"
    debug true
    collectstatic "build_static --noinput"
    database do
      database "#{app_name}"
      engine "postgresql_psycopg2"
      username "#{app_name}"
      password "#{database_password}"
    end
    database_master_role "#{app_name}_database_master"
  end

  gunicorn do
    only_if { node['roles'].include? '#{app_name}_application_server' }
    app_module :django
    port 8080
  end

  celery do
    only_if { node['roles'].include? '#{app_name}_application_server' }
    config "celery_settings.py"
    django true
    celerybeat true
    celerycam true
    broker do
      transport "rabbitmq"
    end
  end

  nginx_load_balancer do
    only_if { node['roles'].include? '#{app_name}_load_balancer' }
    application_port 8080
    static_files "/static" => "static"
  end

end

=begin

# Create the project folder, create a virtualenv
# clone the project repo, install requirements
# To see exactly what this does, checkout providers/build_repo.rb
# This only runs if the project home directory doesn't exist yet
django_deployment_build_repo node.branch do
  action :add
  settings node.settings
  repo node.repo
  app_name node.app_name
  project_root node.project_root
  not_if { File.directory? node.app_home }
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

# Set up restart for nginx
service 'nginx' do
  supports :restart => true, :reload => true
  action :enable
end


# Set up configuration files from templates...

# For gunicorn

template "#{node.app_home}/conf/gunicorn/gunicorn.production.conf" do
  source "gunicorn.production.conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :app_name => node.app_name)
end

# Runner script for gunicorn/supervisor
template "#{node.app_home}/scripts/go_production_gunicorn.sh" do
  source "go_production_gunicorn.sh.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.env_home,
    :app_home => node.app_home)
end

# For supervisor

template "#{node.app_home}/conf/supervisor/#{node.app_name}.conf" do
  source "site_supervisor.conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :project_env => node.env_home,
    :app_home => node.app_home)
end

# For nginx

template "#{node.app_home}/conf/nginx/#{node.app_name}.conf" do
  source "nginx-conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :env_home => node.env_home,
    :app_name => node.app_name,
    :app_home => node.app_home)

end

# symlink conf files into system locations and restart services

link "/etc/supervisor/conf.d/#{node.app_name}.conf" do
  to "#{node.app_home}/conf/supervisor/#{node.app_name}.conf"
  notifies :run, resources(:execute => "supervisor update")
end

link "/etc/nginx/sites-available/#{node.app_name}.conf" do
  to "#{node.app_home}/conf/nginx/#{node.app_name}.conf"
end

link "/etc/nginx/sites-enabled/#{node.app_name}.conf" do
  to "/etc/nginx/sites-available/#{node.app_name}.conf"
  notifies :restart, "service[nginx]"
end


=begin
execute "install-reqs" do
  command "source /home/ubuntu/sites/hello_world/
  && pip install -r /home/ubuntu/sites/hello_world/requirements.txt"
  action :run
  user "ubuntu"
end
=end
