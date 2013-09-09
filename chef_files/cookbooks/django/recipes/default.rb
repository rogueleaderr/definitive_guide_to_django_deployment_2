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

node[:base_packages].each do |pkg|
    package pkg do
        :upgrade
    end
end

node[:users].each_pair do |username, info|
    group username do
       gid info[:id]
    end

    user username do
        comment info[:full_name]
        uid info[:id]
        gid info[:id]
        shell info[:disabled] ? "/sbin/nologin" : "/bin/bash"
        supports :manage_home => true
        home "/home/#{username}"
    end

    directory "/home/#{username}/.ssh" do
        owner username
        group username
        mode 0700
    end

    file "/home/#{username}/.ssh/authorized_keys" do
        owner username
        group username
        mode 0600
        content info[:key]
    end
end

node[:groups].each_pair do |name, info|
    group name do
        gid info[:gid]
        members info[:members]
    end
end
