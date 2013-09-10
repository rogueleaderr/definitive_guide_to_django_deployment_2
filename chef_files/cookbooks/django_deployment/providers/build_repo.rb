action :add do

  repo = new_resource.repo
  branch = new_resource.branch
  app_name = new_resource.app_name
  project_root = new_resource.project_root

  env_name = "#{app_name}-env"
  env_home = "#{project_root}/#{env_name}"
  app_home = "#{project_root}/#{app_name}"

  # Give ownership of the directory that houses the virtualenv to the ubuntu user

  directory "#{project_root}" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  # clone the repo

  git "#{app_home}" do
    repository "https://github.com/#{repo}.git"
    reference "master"
    action :sync
  end

  # ensure ubuntu owns the app folder

  directory "#{app_home}" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
       recursive true
  end

  # ensure directory for scripts, conf, and logging exist
  directory "#{app_home}/scripts" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/log" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/conf" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/conf/gunicorn" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/conf/nginx" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/conf/supervisor" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  directory "#{app_home}/conf/requirements" do
       owner "ubuntu"
       group "ubuntu"
       mode 0775
  end

  # Create the virtualenv

  python_virtualenv "#{env_home}" do
    owner "ubuntu"
    group "ubuntu"
    interpreter "python2.7"
    action :create
  end

  # install the external apps
  # I'm not using the opscode cookbook because there's a bug
  # around installing libraries with c extensions in virtualenvs

  execute "#{env_home}/bin/pip install -r conf/requirements/external_apps.txt" do
    user "ubuntu"
    cwd "#{app_home}"
    only_if "test -f conf/requirements/external_apps.txt"
  end

end
