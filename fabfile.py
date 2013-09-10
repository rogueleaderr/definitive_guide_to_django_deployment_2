import os, json
from tempfile import mkdtemp
from contextlib import contextmanager

from fabric.operations import put
from fabric.api import env, local, sudo, run, cd, prefix, task, settings, execute
from fabric.colors import green as _green, yellow as _yellow
from fabric.context_managers import hide, show
import boto
import boto.ec2
from config import Config
import time

# import configuration variables from untracked config file
f = open("aws.cfg")
cfg = Config(f)
for k in ("aws_access_key_id", "aws_secret_access_key", "region", "key_name",
    "group_name", "ssh_port", "key_dir", "ubuntu_lts_ami"):
    globals()[k] = cfg.get(k)

env.roledefs = {
    'staging_prep': ['root@staging.example.com']
}


STAGING_HOST = 'staging.example.com'
CHEF_VERSION = '10.20.0'

env.key_filename = os.path.expanduser(os.path.join(key_dir, key_name + ".pem"))


#-----FABRIC TASKS-----------

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
@task
def create_instance(name, ami=ubuntu_lts_ami,
                    instance_type='t1.micro',
                    key_name='hello_world_key',
                    key_extension='.pem',
                    key_dir='~/.ec2',
                    group_name='hello_world_group',
                    ssh_port=22,
                    cidr='0.0.0.0/0',
                    tag=None,
                    user_data=None,
                    cmd_shell=True,
                    login_user='ubuntu',
                    ssh_passwd=None):
    """
    Launch an instance and wait for it to start running.
    Returns a tuple consisting of the Instance object and the CmdShell
    object, if request, or None.

    ami        The ID of the Amazon Machine Image that this instance will
               be based on.  Default is a 64-bit Amazon Linux EBS image.

    instance_type The type of the instance.

    key_name   The name of the SSH Key used for logging into the instance.
               It will be created if it does not exist.

    key_extension The file extension for SSH private key files.

    key_dir    The path to the directory containing SSH private keys.
               This is usually ~/.ssh.

    group_name The name of the security group used to control access
               to the instance.  It will be created if it does not exist.

    ssh_port   The port number you want to use for SSH access (default 22).

    cidr       The CIDR block used to limit access to your instance.

    tag        A name that will be used to tag the instance so we can
               easily find it later.

    user_data  Data that will be passed to the newly started
               instance at launch and will be accessible via
               the metadata service running at http://169.254.169.254.

    cmd_shell  If true, a boto CmdShell object will be created and returned.
               This allows programmatic SSH access to the new instance.

    login_user The user name used when SSH'ing into new instance.  The
               default is 'ec2-user'

    ssh_passwd The password for your SSH key if it is encrypted with a
               passphrase.
    """

    print(_green("Started creating {}...".format(name)))
    print(_yellow("...Creating EC2 instance..."))

    conn = connect_to_ec2()

    try:
        key = conn.get_all_key_pairs(keynames=[key_name])[0]
        group = conn.get_all_security_groups(groupnames=[group_name])[0]
    except conn.ResponseError, e:
        setup_aws_account()

    reservation = conn.run_instances(ami,
        key_name=key_name,
        security_groups=[group_name],
        instance_type=instance_type)

    instance = reservation.instances[0]
    conn.create_tags([instance.id], {"Name":name})
    if tag:
        instance.add_tag(tag)
    while instance.state != u'running':
        print(_yellow("Instance state: %s" % instance.state))
        time.sleep(10)
        instance.update()

    print(_green("Instance state: %s" % instance.state))
    print(_green("Public dns: %s" % instance.public_dns_name))

    if raw_input("Add to ssh/config? (y/n) ").lower() == "y":
        ssh_slug = """
        Host {name}
        HostName {dns}
        Port 22
        User ubuntu
        IdentityFile {key_file_path}
        ForwardAgent yes
        """.format(name=name, dns=instance.public_dns_name, key_file_path=os.path.join(os.path.expanduser(key_dir),
            key_name + key_extension))

        ssh_config = open(os.path.expanduser("~/.ssh/config"), "a")
        ssh_config.write("\n{}\n".format(ssh_slug))
        ssh_config.close()

    f = open("fab_hosts/database.txt", "w")
    f.write(instance.public_dns_name)
    f.close()
    return instance.public_dns_name

@task
def terminate_instance(name):
    """
    Terminates all servers with the given name
    """

    print(_green("Started terminating {}...".format(name)))

    conn = connect_to_ec2()
    filters = {"tag:Name": name}
    for reservation in conn.get_all_instances(filters=filters):
        for instance in reservation.instances:
            if "terminated" in str(instance._state):
                print "instance {} is already terminated".format(instance.id)
                continue
            else:
                print instance._state
            print (instance.id, instance.tags['Name'])
            if raw_input("terminate? (y/n) ").lower() == "y":
                print(_yellow("Terminating {}".format(instance.id)))
                conn.terminate_instances(instance_ids=[instance.id])
                print(_yellow("Terminated"))


@task
def install_chef(latest=True):
    """
    Install chef-solo on the server.
    """
    sudo('apt-get update', pty=True)
    sudo('apt-get install -y git-core rubygems ruby ruby-dev', pty=True)
    sudo('apt-get install rsync', pty=True)
    sudo('gem install ruby-shadow')
    if latest:
        sudo('gem install chef --no-ri --no-rdoc', pty=True)
    else:
        sudo('gem install chef --no-ri --no-rdoc --version {0}'.format(CHEF_VERSION), pty=True)

    with settings(hide('warnings', 'stdout', 'stderr'), warn_only=True):
        sudo('mkdir /etc/chef')



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
def bootstrap(name):
    if name == "database":
        f = open("fab_hosts/database.txt")
        env.host_string = "ubuntu@{}".format(f.readline().strip())
        print env.hosts
        #install_chef()
        run_chef()

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


#----------HELPER FUNCTIONS-----------

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


def upload_project_sudo(local_dir=None, remote_dir=""):
    """
    Tars and compresses files on local host and transfers
    them to remote host at specified location
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

def sync_config():
    """
    Download the latest versions of the chef cookbooks that we're going to need.

    Make sure the chef config directory exists, then upload cookbooks and the
    solo.rb file that tells chef where to look for cookbooks.

    TODO: Use rsync to avoid blowing out config. I was having ssh/permission
    issues when I tried
    """
    """
    if raw_input("Chef requires a clean git repo to download new cookbooks. Commit your latest changes now? (y/n)").lower() == "y":
        local("git commit -am 'commiting to allow download of updated cookbooks'")
        node_data = open("chef_files/cookbooks/node.json")
        data = json.load(node_data)
        node_data.close()
        for pkg in data["run_list"]:
            if pkg != "django_deployment":
                with settings(warn_only=True):
                    local("knife cookbook site install {} -o chef_files/cookbooks".format(pkg))
    """
    sudo('mkdir -p /etc/chef')
    upload_project_sudo(local_dir='./chef_files/cookbooks', remote_dir='/etc/chef')
    upload_project_sudo(local_dir='./chef_files/site-cookbooks', remote_dir='/etc/chef')
    upload_project_sudo(local_dir='./chef_files/solo.rb', remote_dir='/etc/chef')
    upload_project_sudo(local_dir='./chef_files/roles', remote_dir='/etc/chef')

def run_chef():
    print "--SYNCING CHEF CONFIG--"
    sync_config()
    print "--RUNNING CHEF--"
    chef_executable = sudo('which chef-solo')
    sudo('cd /etc/chef && sudo %s' % chef_executable, pty=True)
