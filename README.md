#Django in Production - The Definitely Definitive Guide


### Consulting call to action

##Why This Guide Is Needed

Over the last two years, I've taught myself to program in order to
build my startup [LinerNotes.com](http://www.linernotes.com). I
started out expecting that the hardest part would be getting my head
around the sophisticated algorithmic logic of programming. To my
surprise, I've actually had to do very little algorithmic work (Python has existing
libraries that implement nearly any algorithm better than I could.)

Instead, the hardest part has been getting proficient at using the
*many* different tools in the programmer's utility belt. From emacs to
gunicorn, building a real project requires dozens of different
tools. Theoretically, one can *a priori* reason through a red-black
tree. But there's just no way to learn emacs without the reading the
manual. LinerNotes is actually a lot more complicated under the hood
than it is on the surface, so I've had to read quite a lot of
manuals. The point of this guide is to save you some of that trouble.

Sometimes trouble is good. Struggling to design and implement an API builds programming acumen. Struggling to
configure nginx is just a waste of time. I've found many partial
guides to parts of Django deployment but haven't found any single,
recently updated resource that lays out the **simple, Pythonic way of
deploying a Django site in production**.

The goal of this post is to give you an actual production-ready
deployment setup, not to introduce you to basic DevOps concepts. I'll
try to be gentle but won't simplify where doing so would hurt the
quality of the ultimate deployment.

I'm definitely not the most qualified person to write this post, but
it looks like I'm the only one dumb enough to try. If you've got
suggestions about how any part of this process could be better,
*please* comment and I'll update the guide as approriate.

##Overview of the Final Architecture

**By the end of this guide, you should be have a (simple), actually deployed
  Django website accessible at a public IP.** So anyone in the world will be
  able to visit "www.yourapp.com" and see a page that says "Hello World!"

Of course, this is going to be the most well-implemented, stable, and scalable
"hello world" application on the whole world wide web. Here's a diagram of how
your final architecture will look:

![Architecture Diagram](https://raw.github.com/rogueleaderr/definitive_guide_to_django_deployment/master/django_deployment_diagram.png)

Basically, users send HTTP requests to your server, which are intercepted and
routed by the nginx webserver program. Requests for dynamic content will be routed to
your WSGI server (Gunicorn) and requests for static content will be served
directly off the server's file system. Gunicorn has a few helpers, memcached and celery,
which respectively offer a cache for repetitive tasks and an asynchronous queue
for long-running tasks.

We've also got our Postgres database (for all your lovely models) which we run on a
separate EC2 server. You *can* run Postgres on the same VM, but putting it on a
separate box will avoid resource contention and make your app more scalable.

See [below](#services) for a more detailed describe of what each component
actually does.

This article will walk you through the following steps:

1. [Setting up a host server for your webserver and your database](#servers).
2. [Installing and configuring the services your site will need](#services).
3. [Automating deployment of your code](#code).
4. [Setting up monitoring so your site doesn't explode](#monitoring).

##<a id="servers"></a>Set Up the "Physical" Servers

###Set up AWS/EC2

Since this guide is trying to get you to an actual publicly accessible site,
we're going to go ahead and build our site on the smallest, freest Amazon Elastic Compute Cloud
(EC2) instance available, the trusty "micro". If you don't want to use
EC2, you can set up a local virtual machine on your laptop using 
[Vagrant](http://www.vagrantup.com/). I'm also intrigued by the
[Docker project](https://www.docker.io/) that claims to allow deployment of
whole application components in platform agnostic "containers." But Docker
itself says it's not stable enough for production, and who am I to
disagree?[[1]](#note_1)

Anyway, we're going to use EC2 to set up the smallest possible host for our webserver and another
one for our database.

For this tutorial, you'll need an existing EC2 account. There are [many tutorials on setting up an account](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/get-set-up-for-amazon-ec2.html) so I'm not going to walk you through it.

Python has a very nice library called [boto](https://github.com/boto/boto) for administering AWS
from within code. And another nice tool called [Fabric](http://docs.fabfile.org/en/1.7/) for creating
command-line directives that execute Python code that can itself execute
shell commands on local or remote servers. We're going to use Fabric
to definite all of our administrative operations, from
creating/bootstrapping servers up to pushing code. I've read that Chef (which we'll use below) also has a [plugin to launch EC2 servers](http://docs.opscode.com/plugin_knife_ec2.html) but I'm going to prefer boto/Fabric because they give us the option of embedding all the bootstrapping logic into Python and editing it directly as needed.

Start off by cloning the Github repo for this project onto your local machine.

    git clone git@github.com:rogueleaderr/definitive_guide_to_django_deployment.git
    cd definitive_guide_to_django_deployment

I'm assuming that if you want to deploy Django, you already have
Python and pip and [virtualenv](http://www.virtualenv.org/en/latest/)
on your laptop. But just to check:

    python --version
    pip --version
    virtualenv --version

This process requires a number of Python dependencies which we'll
install into a virtualenv (but won't track wtih git):[[2]](#note_2)

    virtualenv django_deployment_env
    source django_deployment_env/bin/activate
    # install all our neccesary dependencies from a requirements file
    pip install -r requirements.txt
    # or, for educational purposes, individually
    pip install boto
    pip install fabric
    pip install awscli

The github repo includes a fabfile.py[[3]](#cred_1) which provides all the
commandline directives we'll need. But fabfiles are pretty intuitive
to read, so try to follow along with what each command is doing.

First, we need to set up AWS credentials for boto to use. In keeping
with the principles of the [Twelve Factor App](http://12factor.net/)
we store configuration either in environment variables or in config
files which are not tracked by VCS.

    echo '
    aws_access_key_id: <YOUR KEY HERE>
    aws_secret_access_key: <YOUR SECRET KEY HERE>
    region: "<YOUR REGION HERE, e.g. us-east-1>"
    key_name: hello_world_key
    key_dir: "~/.ec2"
    group_name: hello_world_group
    ssh_port: 22
    ubuntu_lts_ami: "ami-d0f89fb9"' > aws.cfg
    echo "aws.cfg" >> .gitignore

(An "AMI" is an Amazon Machine Image, and the one we've chosen corresponds to a
"free-tier" eligible Ubuntu image.)

While we're at it, let's create a config file that will let you use
the AWS CLI directly:

    mkdir ~/.aws
    echo '
    aws_access_key_id = <YOUR KEY HERE>
    aws_secret_access_key = <YOUR SECRET KEY HERE>
    region = <YOUR REGION HERE, e.g. us-east-1>' > ~/.aws/config


Now we're going to use a Fabric directive to setup our AWS account[[4]](#cred_2) by:

1. Configuring a keypair ssh key that will let us log in to our servers
2. Setup a security group that defines access rules to our servers

To use our first fabric directive and setup our AWS account, go to the directory where our fabfile lives and
do

    fab setup_aws_account

###Launch EC2 Servers

We're going to launch 2 Ubuntu 12.04 LTS servers, one for our web host
and one for our database. We're using Ubuntu because it it seems to be
the most popular linux distro right now, and 12.04 because it's a (L)ong (T)erm (S)upport
version, meaning we have the longest period before it's official
deprecated and we're forced to deal with an OS upgrade.

With boto and Fabric, launching a new instance is very easy:

    fab create_server:webserver
    fab create_server:database

These commands tell Fabric to use boto to create a new "micro"
(i.e. free for the first year) instance on EC2, with the name you
provide. You can also provide a lot more configuration options to this
directive at the command line but the defaults are sensible for now.

You'll also be given the option to add the instance information to
your ~/.ssh/config file so that you can login to your instance
directly with

    ssh webserver

If you create an instance by mistake, you can terminate it with

    fab terminate_instance webserver

(You'll have to manually delete the ssh/config entry)


##<a id="services"></a>Install and Configure Your Services

###Understand the services
Our app is made up of a number of services that run
semi-independently:

**Gunicorn**: Our
  [WSGI](http://wsgi.readthedocs.org/en/latest/what.html)[[5]](#cred_3)
  webserver. Gunicorn receives HTTP requests fowarded to it from nginx, executes
  our Django code to produce a response, and returns the response which nginx transmits back to the client.
  
**Nginx**: Our
  "[reverse proxy](http://en.wikipedia.org/wiki/Reverse_proxy)"
  server. Nginx takes requests from the open internet and decides
  whether they should be passed to Gunicorn, served a static file,
  served a "Gunicorn is down" error page, or even blocked (e.g. to prevent denial-of-service
  requests.)

**Memcached**: A simple in-memory key/value caching system. Can save
  Gunicorn a lot of effort regenerating rarely-changed pages or objects.

**Celery**:   An async task system for Python. Can take longer running
  bits of code and process them outside of Gunicorn without jamming up
  the webserver. Can also be used for "poor man's" concurrency in Django.

**RabbitMQ**: A queue/message broker that passes asynchronous tasks
  between Gunicorn and Celery.

**Supervisor**: A process manager that attempts to make sure that all key services stay
  alive and are automatically restarted if they die for any reason.

**Postgres**: The main database server ("cluster" in Postgres
  parlance"). Contains one or more "logical" databases containing our
  application data / model data.
  
###Install the services

We could install and configure each service individually, but instead
we're going to use a "configuration automation" tool called
[Chef](http://www.opscode.com/chef/). Chef lets us write simple Ruby
programs (sorry Python monogamists!) called Cookbooks that automatically
install and configure services.

Chef can be a bit intimidating. It provides an entire Ruby-based
domain specific language (DSL) for expressing configuration. And it
also provides a whole system (Chef server) for controlling the
configuration of remote servers (a.k.a. "nodes") from a central location. The DSL is
unavoidable, but we can make things a bit simpler by using "Chef Solo"
which is does away with the whole central server and leaves us with
just a single script that we run on our remote servers to bootstrap our
configuration.

Hat tip to several authors for blog posts about using Chef for Django[[6]](#cred_4)

Make sure we have the latest version of the approriate cookbooks:

knife cookbook site install git -o cookbooks

Copy your user public key into the node.json user key slot

cat ~/.ssh/id_rsa.pub | pbcopy


Install Ruby:

    #brew install rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zshrc
    echo 'eval "$(rbenv init -)"' >> ~/.zshrc
    rbenv install 1.9.3-p448
    rbenv global 1.9.3-p448

Install [Berkshelf](http://berkshelf.com/) and Chef-Rewind:

    gem install bundler
    sudo gem install berkshelf
    # tell Berkshelf to install cookbooks into our folder instead of ~/.berkshelf
    export BERKSHELF_PATH=chef_files

Use Berkshelf to install the cookbooks we'll need:

    berks install

Now we're going to use Fabric to tell Chef to bootstrap our webserver. Do:

    fab bootstrap:database

This will:

1. Install Chef
2. Tell Chef to configure the server

Okay, buckle up. We're going to need to talk a little about how Chef works. But it'll be worth it.

At the root, Chef is made up of small Ruby scripts called *recipes* that express
configuration. Chef *declares* configuration rather than executing a
series of steps (like Fabric does), i.e. a recipe is supposed to describe all the resources that
are available on a server (rather than just invoking installation
commands.) If a resource is missing when a recipe is run, Chef will
try to figure out how to install that resource. But recipes are
(supposed to be) *idempotent*, meaning that if you run a recipe and
then run it again then the second run will have no effects.

But which recipes to run? Chef organizes recipes into *cookbooks* that
group together recipes for working with a specific tool (e.g. "the git
cookbook"). And Chef has a concept called "roles" that let you specify
which cookbooks should be used on a given server. So for example, we
can define a "webserver" role and tell Chef to use the "git", "nginx"
and "django" cookbooks. Opscode (the makers of Chef) provide a bunch
of pre-packaged and (usually well maintained) cookbooks for common
tools like git. These are what we installed with Berkshelf (above).

Chef cookbooks can get quite complicated, but they are just code and so they can be version controlled with git. Chef mavens recommend storing as much configuration as possible in cookbooks (instead of in roles) because it's easier to test or rollback changes to a cookbook. **WHY?**

We have one role for the webserver:

    cat chef_files/roles/web.rb

And we invoke Chef-solo with a tiny Ruby script that tells Chef where to find our cookbooks and roles:

    cat chef_files/solo_webserver.rb




    

http://berkshelf.com/


##<a id="code"></a>Deploy Your Code

##<a id="monitoring"></a>Set Up Monitoring

##Go Hard


By far the most likely problem you might face is that one of the services has died for
some silly reason and failed to automatically restart.

###Logging in to servers

You can SSH into each of the servers from any terminal. All you need is SSH keys which
I've left in the shared dropbox.



To login, do:
 

Instructions by Service:
----

###Nginx

Nginx is the proxy server that routes HTTP traffic. In 6 months, it has never once gone
down for me. It should start automatically if the webserver restarts.

If you need to start/restart nginx, log in to the webserver and do:

    sudo service nginx restart

If nginx misbehaves, logs are at:

    /var/log/nginx/

If, for some reason, you need to edit the nginx configuration file it's at:

    sudo emacs /etc/nginx/sites-available/hello.conf

###Memcached

Memcached is also a service and starts automatically if the webserver restarts. The site
should also continue to function if it dies (just be slow). Caching issues can sometimes
cause weird page content, so if something seems unusually bizarre try flushing the cache
by restarting memcached:

    sudo service restart memcached

Memcached is pretty fire and forget...since it's in memory it's theoretically possible it
could fill up and exhaust the memory on the webserver (I don't have a size cap and ttl's
are very long) but that has never happened so far. If it does, just reset memcached and it
will clear itself out.


###RabbitMQ

Another service that's started automatically. I have literally never had to interact
directly with it. But if can also be restarted by

    sudo service restart rabbitmq

###Gunicorn/Celery

Gunicorn is the WSGI webserver that runs all the LinerNotes Python code. The code all
lives in

    cd /var/www/hello-env/hello

All the Python dependency libraries live inside of a ["virtual environment"](http://www.virtualenv.org/en/latest/).
If you need to activate it, just do:

    # to activate venv:
    source /var/www/hello-env/bin/activate

Celery doesn't actually run code on its own, but it maintains "worker" process that can
execute tasks handed to it by Gunicorn (via RabbitMQ). The task code is defined in the
same main Django folder.


#### To start Gunicorn/Celery:

Gunicorn and the Celery Workers are controlled by *Supervisor*, which is a Linux process runner/controller. Supervisor starts
Gunicorn and Celery when the EC2 server starts and will automatically restart them if
they're terminated abnormally.

The Supervisor configuration is located at:

    /etc/supervisor/conf.d/hello_startup.conf

That conf file tells supervisor to try to run two bash scripts that actually set up
dependencies for and run gunicorn and celery. Those runner scripts are located at:

    /var/www/hello-env/hello/hello/scripts/go_production_gunicorn.sh
    /var/www/hello-env/hello/hello/scripts/go_production_celery.sh

Superviosr provides a utility *supervisorctl* that lets you check the status of and
restart processes. So if you need to restart gunicorn or celery, you can do:

    sudo supervisorctl -c /etc/supervisor/supervisord.conf restart gunicorn
    sudo supervisorctl -c /etc/supervisor/supervisord.conf restart celery

Or to check process status, just do

    sudo supervisorctl -c /etc/supervisor/supervisord.conf status

Obviously, gunicorn and celery should always say "RUNNING"

Gunicorn is configured with a conf file that can be found at:

    emacs /var/www/hello-env/hello/hello/conf/gunicorn/gunicorn.conf

Gunicorn's key log files are:

    /var/www/hello-env/hello/hello/log/gunicorn.error.log
    /var/www/hello-env/hello/hello/log/gunicorn.log

Django and Celery also log at:

    /var/www/hello-env/hello/hello/log/django.log
    /var/www/hello-env/hello/hello/log/celery.log

I keep a [GNU screen](http://www.gnu.org/software/screen/) active in the log directory so
I can get there quickly if I need to. You can get there with

    screen -r 26334.pts-3.ip-10-145-149-233


###ElasticSearch

ElasticSearch is a Lucene-based search system that automatically clusters across nodes
it's installed on and automatically replicates and restores itself if a node goes
down. It runs as a service so it starts automatically if a node reboots.

ElasticSearch is generally pretty stable, but is nonetheless probably the most fragile part of the stack. But luckily if it goes down
the whole site won't die -- it'll just make searches return "no results" which is bad but
not world-ending.

But I'm making a couple of cost-compromises that make it less resiliant.

1) I'm using a probably-smaller-than-approriate server with minimal memory and disk space.

2) Instead of a real cluster with proper replication, I'm using an EC2 "spot" instance as the second node in the cluster. These are way
cheap, but they can randomly terminate at any time.

This setup is only a problem if *both* the spot instance terminates *and* the main HEAD
instance blows up and cna't recover. In that case, ES will lose data and not be able to restore itself
unless I reconstruct the index (which is complicated and takes several hours.) If that
happens, just try to call/text/notify me and I'll decide what to do.

If you need to restart ES for some reason (try not to, because it takes a while to reload
from disk) you can do:
    
    # (login to the ES node)
    sudo service elasticsearch restart

###Postgres

Postgres is a very stable program but my configuration can be a bit touchy. It's probably
the most likely component to give you trouble (and sadly the site becomes totally
non-operational if it goes down.)

I have three logical databases running the "cluster" (PG lingo for a server):

* linernotes_data -- immutable custom generated metadata
* musicbrainz_db -- a replication of the full musicbrainz database
* django_db -- my main Django database with all the user info etc.

Postgres runs as a service so if you need to restart it (try not to need to do this) you
can do:

    sudo service postgresql restart

My postgres database is very large (~200GB) and I'm running in on the smallest/cheapest
server I can. That means it can sometimes run out of memory and die under heavy
load. Usually it will just restart itself if this happens, but sometimes it gets stuck
replaying a WAL log and requires you to delete a file to get going again. This has only
happened a couple of times ever, and when it did the logs had instructions for how to fix
it. So if the database goes down and won't restart, check the logs for help.



The disk can also fill (especially if something gets weird with the logging.) I cleared a
bunch of extra space before leaving but check:

    df -h

If things get weird.

I have several backup schemes, but because the database is so large a full restore takes
hours. So try not to corrupt the data :)

Just in case, I made backups of each logical database. These can be restored fully or even
table-by-table, but be warned it can take hours since the DB's are large. Obviously try
hard to avoid needing to do this.

    # to restore linernotes_data
    pg_restore -C -d postgres /mnt/backup/2013_08_22/linernotes_data.pg
    # to restore musicbrainz_db
    pg_restore -C -d postgres /mnt/backup/2013_08_22/musicbrainz_db.pg
    # to restore django_db
    pg_restore -C -d postgres /mnt/backup/2013_08_22/django_db.pg

[Full directions on pg_restore are here](http://www.postgresql.org/docs/9.2/static/app-pgrestore.html)

These backups are kept on an "instance store" disk that will be wiped if the postgres EC2
server is stopped (but not if it's rebooted). In case that happens, I've created a full
"image" in AWS of the Postgres server which you can create a full new server from. That
will roll all the data back to where it was when I left (including user data) but it's
better than keeping the site down if it's the only choice.

See the next section for how to log into AWS. See [these directions for how to launch a
server from an AMI (Amazon Machine Image)](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/LaunchingAndUsingInstances.html).

I also made an image of the webserver and of the ElasticSearch node.

    ami-23b2f14a -- Postgres
    ami-0760236e -- Webserver
    ami-ad8ac9c4 -- ElasticSearch
    
Images can be [seen on this page](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Images:)

If you have to recreate a server, make sure you reattach the old *Elastic IP* or the app won't
know where to find resources. See [here for directions on ElasticIP's](http://docs.aws.amazon.com/AmazonVPC/latest/GettingStartedGuide/EIP.html)

Static Files
-----------

All static files (JS, CSS, images) are served out of Amazon S3 from the
"linernotes\_static\_public" bucket. If the site suddenly loses all of it's CSS, check
that S3 is working and that the static files/bucket are in place and working. If Amazon
for some reason changes the S3 paths, the app defines the static paths in

    /var/www/hello-env/hello/hello//hello/settings/base.py

Under the "STATIC_ROOT" variable.

If you need to modify static files (e.g. edit JS), you can upload new static files to S3
by running

    python manage.py collectstatic

From the project root directory (wth a virtualenv enabled) or just run the "git\_to\_prod"
script which includes static collection as a step.

Notifications / PagerDuty
-------------

*PagerDuty* is a website that will call or email you if something goes wrong with a
 server. I've configured it to email/SMS you if anything goes wrong with the site. If you
 get a notication, check to make sure that it's not a false alarm, fix the problem (if
 needed) and reply to PagerDuty that you resolved the issue.

Django also also automatically emits error emails, which I:

1) route to PagerDuty so it automatically sets up an "incident" and SMS's you
2) sends an email to you with the details of the error

Occasionally these emails are for non-serious issues but there's no easy way to
filter. Below I've listed a few "non-problems" that you can safely ignore.


Most Likely Errors
------

###Failed service restart

All of the services are set up to automatically restart themselves if they die or if their
host server restarts. So the only time they should be a problem is they both die **and** a
wrench gets in the works making the server unable to restart.

The most likely cause of somethig like that is a disk overflow. Each of the disks should
have plenty of space, but if something goes crazy with logging they could somehow
overflow. If that happens, use

    df -h

To check disk space. If a disk is 99% full, find big files using

    find / -type f -name *.tar.gz -size +10M -exec ls -l {} \;

EC2 instances all have "instance store" disks on /mnt, so you can copy obviously
suspicious files onto the instance store and let me sort it out later (please make a note
of what you move and from/to where).

If that's not enough, check the logs for the service (log dirs should be listed for all
key components above) and see if there is an obvious problem.

###Traffic spike

No likely, and I've benchmarked the site to handle 2k simultaneous users. If traffic
knocks the site down, there's not much you can do. You can try stopping servers in EC2
console and using "change instance type" to upgrade to a larger server. Other than that,
I'll have to put in a load balancer and more webservers which is out of scope.

###Random EC2 server death/restart

Once in a blue moon, EC2 will decide a server needs to be retired and terminate it. If
that happens, recreate a new version of the server from an image.

False Flag Problems
-----

(These are non-serious issues I just haven't been able to fix yet)

###TimedOut

Once in a while a request will time out and send an email. Unless it's happening a lot,
don't worry.

###QueuePool error

I use a client-side Postgres connection pooler. Under heavy load, sometimes the pool gets
exhausted and Django doesn't cope well with that. Basically just ignore these unless
they're happening a lot, then check if traffic has gone crazy or the database if failed

###ForeignKey error

Sometimes data I injest from API's has non-unique primary keys. DJango no like, but I
haven't figured out how to prevent. Just ignore.

###Max retries exceeded with url

My http lib sometimes throws uncatchable exceptions if an API connection times
out. Generally just ignore unless it's happening a lot.

Datadog Monitoring
------

I use a cool service called Datadog that makes pretty metric dashboards. It also sends an
alert if there's no CPU activity from the webserver or the database (probably meaning the
EC2 servers are down.)

You can [look at it here]()


US PG BOUNCER

##Bibliography
[Randall Degges rants on deployment](http://www.rdegges.com/deploying-django/)

[Rob Golding on deploying Django](http://www.robgolding.com/blog/2011/11/12/django-in-production-part-1---the-stack/)

[Aqiliq on deploying Django on Docker](http://agiliq.com/blog/2013/06/deploying-django-using-docker/)

[Kate Heddleston's Talk on Chef at Pycon 2013](http://pyvideo.org/video/1756/chef-automating-web-application-infrastructure)

[Honza's django-chef repo](https://github.com/honza/django-chef)


[1]<a href id="cred_1"></a> Hat tip to Martha Kelly for [her post on using Fabric/Boto to deploy EC2](http://marthakelly.github.io/blog/2012/08/09/creating-an-ec2-instance-with-fabric-slash-boto/)

[2]<a href id="cred_2"></a> Hat tip to garnaat for
[his AWS recipe to setup an account with boto](https://github.com/garnaat/paws/blob/master/ec2_launch_instance.py)

[3] [More about WSGI](http://agiliq.com/blog/2013/07/basics-wsgi/)

[4] ["Building a Django App Server with Chef, Eric Holscher"](http://ericholscher.com/blog/2010/nov/8/building-django-app-server-chef/); ["An Experiment With Chef Solo", jamiecurle]("https://github.com/jamiecurle/ubuntu-django-chef-solo-config");

##Notes
[1]<a href id="note_1"></a> (But *you* should really consider writing a guide to deploying Django
using Docker so I can link to it.)

[2]<a href id="note_2"></a>For development I enjoy [VirtualenvWrapper](http://virtualenvwrapper.readthedocs.org/en/latest/) which makes switching between venv's easy. But it installs venvs by default in a ~/Envs home directory and for deployment we want to keep as much as possible inside of one main project directory (to make everything easy to find.)

add net.core.somaxconn=1024 to /etc/sysctl.conf

cache-machine
