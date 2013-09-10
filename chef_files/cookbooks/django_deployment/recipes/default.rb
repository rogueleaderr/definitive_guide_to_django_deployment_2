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

execute "Update apt repos" do
    command "apt-get update"
end

include_recipe 'nginx'
include_recipe 'python'
include_recipe 'git'

node[:base_packages].each do |pkg|
    package pkg do
        :upgrade
    end
end

node[:pip_python_packages].each do |pkg|
    execute "install-#{pkg}" do
        command "pip install #{pkg}"
        not_if "[ `pip freeze | grep #{pkg} ]"
    end
end

directory "/home/ubuntu/sites" do
  owner "ubuntu"
  mode "0770"
  action :create
  not_if "test -d /home/ubuntu/sites"
  recursive true
end

python_virtualenv "/home/ubuntu/sites/hello_world/" do
 owner "ubuntu"
 action :create
end

execute "install-reqs" do
  command "source /home/ubuntu/sites/hello_world/
  && pip install -r /home/ubuntu/sites/hello_world/requirements.txt"
  action :run
  user "ubuntu"
end
