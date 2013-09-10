action :add do

  repo = new_resource.repo
  branch = new_resource.branch
  app_name = new_resource.app_name
  env_root = new_resource.env_root

  env_name = "#{app_name}-env"
  project_home = "#{env_root}/#{env_name}"

  # Give ownership of the directory that houses the virtualenv to the ubuntu user

  directory "#{env_root}" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  # ensure directory for scripts, conf, and logging exist

  directory "#{env_root}/scripts" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{env_root}/log" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{env_root}/conf" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{env_root}/conf/gunicorn" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{env_root}/conf/nginx" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{env_root}/conf/supervisor" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  # Create the virtualenv

  python_virtualenv "#{project_home}" do
    owner "ubuntu"
    group "ubuntu"
    interpreter "python2.7"
    action :create
  end

  # clone the repo

git "#{app_home}" do
  repository "https://github.com/#{repo}.git"
  reference "master"
  action :sync
end

  # install the external apps
  # I'm not using the opscode cookbook because there's a bug
  # around installing libraries with c extensions in virtualenvs

  execute "#{project_home}/bin/pip install -r conf/external_apps.txt" do
    user "ubuntu"
    cwd "#{app_home}"
  end

end
