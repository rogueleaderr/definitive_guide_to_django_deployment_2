name "web"

# `env_root` is the location to create a virtualenv
# the virtual env will have the name `app_name`-env
# `repo` is the github repo, assumed to be public, cloned into `env_root`/`app_name`-env/`app_name`
# `settings` is the settings file, assumed to be in settings/ at your repo's root


default_attributes("site_domain" => "yourawsmdomain.ly",
                   "project_root" => "/home/ubuntu/sites",
                   "app_name" =>"hello_world",
                   "repo" => "zmsmith/djangohelloworld",
                    "settings" => "__init__.py",
                    "base_packages" => "bash-completion",
                    "ubuntu_python_packages" => ["python-setuptools",
                    	"python-pip",
                    	"python-dev",
                    	"libpq-dev"],
                    "pip_python_packages" => "virtualenv"
                    )

run_list "recipe[django_deployment]",
	"recipe[git]",
	"recipe[apt]",
	"recipe[nginx]",
	"recipe[python]",
	"recipe[python]",
	"recipe[nginx]"




