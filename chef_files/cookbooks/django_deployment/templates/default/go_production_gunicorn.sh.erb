#!/bin/bash

NAME="gunicorn"                                  # Name of the application
DJANGODIR=<%= @app_home %>             # Django project directory
USER=ubuntu                                       # the user to run as
VENV_DIR=<%= @env_home %>
DJANGO_SETTINGS_MODULE=<%= @app_name %>.settings
DJANGO_WSGI_MODULE=<%= @app_name %>.wsgi                     # WSGI module name

echo "Starting $NAME"

# Activate the virtual environment
cd $DJANGODIR
source $VENV_DIR/bin/activate
export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE
export PYTHONPATH=$DJANGODIR:$VENV_DIR:$PYTHONPATH
export ENVIRONMENT_SETTING_FILE=production.settings
export STAGE=production
export LOGGING_DIR=$DJANGODIR

# Start your Django Unicorn
# Programs meant to be run under supervisor should not daemonize themselves (do not use --daemon)
exec gunicorn wsgi:application -c conf/gunicorn/gunicorn.conf
