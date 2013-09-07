import os
from tempfile import mkdtemp
from contextlib import contextmanager

from fabric.operations import put
from fabric.api import env, local, sudo, run, cd, prefix, task, settings
from fabric.colors import green as _green, yellow as _yellow
import boto
import boto.ec2
from config import Config
import time

f = open("aws.cfg")
cfg = Config(f)
print cfg
for k in ("aws_access_key_id", "aws_secret_access_key", "region", "key_name", "group_name", "ssh_port", "key_dir"):
    globals()[k] = cfg.get(k)
    print(k, globals()[k])

env.roledefs = {
    'staging_prep': ['root@staging.example.com']
}


STAGING_HOST = 'staging.example.com'
CHEF_VERSION = '10.20.0'

env.root_dir = '/opt/example/apps/example'
env.venvs = '/opt/example/venvs'
env.virtualenv = '%s/example' % env.venvs
env.activate = 'source %s/bin/activate ' % env.virtualenv
env.code_dir = '%s/src' % env.root_dir
env.media_dir = '%s/media' % env.root_dir


@contextmanager
def _virtualenv():
    with prefix(env.activate):
        yield


def _manage_py(command):
    run('python manage.py %s --settings=example.settings_server'
            % command)

def connect_to_ec2():
    """
    return a connection given credentials imported from config
    """
    return boto.ec2.connect_to_region(region,
    aws_access_key_id=aws_access_key_id,
    aws_secret_access_key=aws_secret_access_key)

@task
def setup_aws_account():

    ec2 = connect_to_ec2()

    # Check to see if specified keypair already exists.
    # If we get an InvalidKeyPair.NotFound error back from EC2,
    # it means that it doesn't exist and we need to create it.
    try:
        key = ec2.get_all_key_pairs(keynames=[key_name])[0]
        print "key name {} already exists".format("key_name")
    except ec2.ResponseError, e:
        if e.code == 'InvalidKeyPair.NotFound':
            print 'Creating keypair: %s' % key_name
            # Create an SSH key to use when logging into instances.
            key = ec2.create_key_pair(key_name)

            # Make sure the specified key_dir actually exists.
            # If not, create it.
            global key_dir
            key_dir = os.path.expanduser(key_dir)
            key_dir = os.path.expandvars(key_dir)
            if not os.path.isdir(key_dir):
                os.mkdir(key_dir, 0700)

            # AWS will store the public key but the private key is
            # generated and returned and needs to be stored locally.
            # The save method will also chmod the file to protect
            # your private key.
            key.save(key_dir)
        else:
            raise

    # Check to see if specified security group already exists.
    # If we get an InvalidGroup.NotFound error back from EC2,
    # it means that it doesn't exist and we need to create it.
    try:
        group = ec2.get_all_security_groups(groupnames=[group_name])[0]
    except ec2.ResponseError, e:
        if e.code == 'InvalidGroup.NotFound':
            print 'Creating Security Group: %s' % group_name
            # Create a security group to control access to instance via SSH.
            group = ec2.create_security_group(group_name,
                                              'A group that allows SSH access')
        else:
            raise

    # Add a rule to the security group to authorize SSH traffic
    # on the specified port.
    try:
        group.authorize('tcp', ssh_port, ssh_port, "0.0.0.0/0")
    except ec2.ResponseError, e:
        if e.code == 'InvalidPermission.Duplicate':
            print 'Security Group: %s already authorized' % group_name
        else:
            raise

def create_server():
    """
    Creates EC2 Instance
    """
    print(_green("Started..."))
    print(_yellow("...Creating EC2 instance..."))

    conn = connect_to_ec2()

    image = conn.get_all_images(ec2_amis)

    reservation = image[0].run(1, 1, key_name=ec2_key_pair, security_groups=ec2_security,
        instance_type=ec2_instancetype)

    instance = reservation.instances[0]
    conn.create_tags([instance.id], {"Name":config['INSTANCE_NAME_TAG']})
    while instance.state == u'pending':
        print(_yellow("Instance state: %s" % instance.state))
        time.sleep(10)
        instance.update()

    print(_green("Instance state: %s" % instance.state))
    print(_green("Public dns: %s" % instance.public_dns_name))

    return instance.public_dns_name

@task
def install_chef(latest=True):
    """
    Install chef-solo on the server
    """
    sudo('apt-get update', pty=True)
    sudo('apt-get install -y git-core rubygems ruby ruby-dev', pty=True)

    if latest:
        sudo('gem install chef --no-ri --no-rdoc', pty=True)
    else:
        sudo('gem install chef --no-ri --no-rdoc --version {0}'.format(CHEF_VERSION), pty=True)

    sudo('gem uninstall --no-all --no-executables --no-ignore-dependencies json')
    sudo('gem install json --version 1.7.6')


def parse_ssh_config(text):
    """
    Parse an ssh-config output into a Python dict.

    Because Windows doesn't have grep, lol.
    """
    try:
        lines = text.split('\n')
        lists = [l.split(' ') for l in lines]
        lists = [filter(None, l) for l in lists]

        tuples = [(l[0], ''.join(l[1:]).strip().strip('\r')) for l in lists]

        return dict(tuples)

    except IndexError:
        raise Exception("Malformed input")


def set_env_for_user(user='example'):
    if user == 'vagrant':
        # set ssh key file for vagrant
        result = local('vagrant ssh-config', capture=True)
        data = parse_ssh_config(result)

        try:
            env.host_string = 'vagrant@127.0.0.1:%s' % data['Port']
            env.key_filename = data['IdentityFile'].strip('"')
        except KeyError:
            raise Exception("Missing data from ssh-config")


@task
def up():
    """
    Provision with Chef 11 instead of the default.

    1.  Bring up VM without provisioning
    2.  Remove all Chef and Moneta
    3.  Install latest Chef
    4.  Reload VM to recreate shared folders
    5.  Provision
    """
    local('vagrant up --no-provision')

    set_env_for_user('vagrant')

    sudo('gem uninstall --no-all --no-executables --no-ignore-dependencies chef moneta')
    install_chef(latest=False)
    local('vagrant reload')
    local('vagrant provision')


@task
def bootstrap():
    set_env_for_user('vagrant')

    # Bootstrap
    run('test -e %s || ln -s /vagrant/src %s' % (env.code_dir, env.code_dir))
    with cd(env.code_dir):
        with _virtualenv():
            run('pip install -r requirements.txt')
            _manage_py('syncdb --noinput')
            _manage_py('migrate')
            _manage_py('createsuperuser')

@task
def hello():
    print("Hello world!")
    a = local("echo hello").stdout
    print "zoinks"
    print a

@task
def push():
    """
    Update application code on the server
    """
    with settings(warn_only=True):
        remote_result = local('git remote | grep %s' % env.remote)
        if not remote_result.succeeded:
            local('git remote add %s ssh://%s@%s:%s/opt/example/apps/example' %
                (env.remote, env.user, env.host, env.port,))

        result = local("git push %s %s" % (env.remote, env.branch))

        # if push didn't work, the repository probably doesn't exist
        # 1. create an empty repo
        # 2. push to it with -u
        # 3. retry
        # 4. profit

        if not result.succeeded:
            # result2 = run("ls %s" % env.code_dir)
            # if not result2.succeeded:
            #     run('mkdir %s' % env.code_dir)
            with cd(env.root_dir):
                run("git init")
                run("git config --bool receive.denyCurrentBranch false")
                local("git push %s -u %s" % (env.remote, env.branch))

    with cd(env.root_dir):
        # Really, git?  Really?
        run('git reset HEAD')
        run('git checkout .')
        run('git checkout %s' % env.branch)

        sudo('chown -R www-data:deploy *')
        sudo('chown -R www-data:deploy /opt/example/venvs')
        sudo('chmod -R 0770 *')


@task
def deploy():
    set_env_for_user(env.user)

    push()
    sudo('chmod -R 0770 %s' % env.virtualenv)

    with cd(env.code_dir):
        with _virtualenv():
            run('pip install -r requirements.txt')
            run('python manage.py collectstatic --clear --noinput --settings=example.settings_server')
            run('python manage.py syncdb --noinput --settings=example.settings_server')
            run('python manage.py migrate --settings=example.settings_server')

    restart()


@task
def restart():
    """
    Reload nginx/gunicorn
    """
    with settings(warn_only=True):
        sudo('supervisorctl restart app')
        sudo('/etc/init.d/nginx reload')


@task
def vagrant(username):
    # set ssh key file for vagrant
    result = local('vagrant ssh-config', capture=True)
    data = parse_ssh_config(result)

    env.remote = 'vagrant'
    env.branch = 'master'
    env.host = '127.0.0.1'
    env.port = data['Port']

    try:
        env.host_string = '%s@127.0.0.1:%s' % (username, data['Port'])
    except KeyError:
        raise Exception("Missing data from ssh-config")


@task
def staging(username):
    env.remote = 'staging'
    env.branch = 'master'
    env.host = STAGING_HOST
    env.port = 22
    env.host_string = '%s@%s:%s' % (username, env.host, env.port)


def upload_project_sudo(local_dir=None, remote_dir=""):
    """
    Copied from Fabric and updated to use sudo.
    """
    local_dir = local_dir or os.getcwd()

    # Remove final '/' in local_dir so that basename() works
    local_dir = local_dir.rstrip(os.sep)

    local_path, local_name = os.path.split(local_dir)
    tar_file = "%s.tar.gz" % local_name
    target_tar = os.path.join(remote_dir, tar_file)
    tmp_folder = mkdtemp()

    try:
        tar_path = os.path.join(tmp_folder, tar_file)
        local("tar -czf %s -C %s %s" % (tar_path, local_path, local_name))
        put(tar_path, target_tar, use_sudo=True)
        with cd(remote_dir):
            try:
                sudo("tar -xzf %s" % tar_file)
            finally:
                sudo("rm -f %s" % tar_file)
    finally:
        local("rm -rf %s" % tmp_folder)


@task
def sync_config():
    sudo('mkdir -p /etc/chef')
    upload_project_sudo(local_dir='./cookbooks', remote_dir='/etc/chef')
    upload_project_sudo(local_dir='./roles/', remote_dir='/etc/chef')


@task
def provision():
    """
    Run chef-solo
    """
    sync_config()

    node_name = "node_%s.json" % (env.roles[0].split('_')[0])

    with cd('/etc/chef/cookbooks'):
        sudo('chef-solo -c /etc/chef/cookbooks/solo.rb -j /etc/chef/cookbooks/%s' % node_name, pty=True)


@task
def prepare():
    install_chef(latest=False)
    provision()
