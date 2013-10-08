#
# Cookbook Name:: django_application_server
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

include_recipe "git"
include_recipe "apt"
include_recipe "nginx"
include_recipe "python"
include_recipe "nginx"
include_recipe "rabbitmq"
include_recipe "build-essential"
include_recipe "postgresql::client"
include_recipe "postgresql::server"
include_recipe "application"

node.default["env_name"] = "#{node.app_name}-env"
node.default["env_home"] = "#{node.project_root}/#{node.env_name}"
node.default["app_home"] = "#{node.project_root}/#{node.app_name}"

# a ridiculously roundable way of getting the node variable into the block
db_line = <<HERE
			database  "#{node.app_name}"
			engine  "postgresql_psycopg2"
			username  "#{node.app_name}"
			password  "#{node.database_password}"
HERE
puts "DB LINE #{db_line}"
proc_line = "Proc.new { '#{db_line}' }"
puts "PROcc #{proc_line}"
node.default[:database] = eval "Proc.new { puts 7777777 }"
puts "DEFF #{node[:database]}"

=begin
execute "Update apt repos" do
    command "apt-get update"
end
=end

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

application "#{node.app_name}" do
	only_if { node['roles'].include? 'application_server' }
	path "/srv/#{node.app_name}"
	owner "nobody"
	group "nogroup"
	repository "https://github.com/#{node.repo}.git"
	revision "master"
	migrate true

	django do
		requirements "requirements/requirements.txt"
		settings_template "settings.py.erb"
		debug true
		collectstatic "build_static --noinput"
		database_host "localhost"
		database_name  "#{node.app_name}"
		database_engine  "postgresql_psycopg2"
		database_username  "#{node.app_name}"
		database_password  "#{node.database_password}"
		database do
			database "packaginator"
			engine "postgresql_psycopg2"
			username "packaginator"
			password "awesome_password"
		end
		database_master_role "database_master"
	end

	gunicorn do
		only_if { node['roles'].include? 'application_server' }
		app_module :django
		port 8080
	end

	celery do
		only_if { node['roles'].include? 'application_server' }
		config "celery_settings.py"
		django true
		celerybeat true
		celerycam true
		broker do
			transport "rabbitmq"
			host "localhost"
		end
	end

	nginx_load_balancer do
		only_if { node['roles'].include? '#{app_name}_load_balancer' }
		application_port 8080
		static_files "/static" => "static"
	end

end
