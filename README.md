The definitely definitive guide to deploying Django in Production
===

### Consulting call to action

##Why This Guide Is Needed

Over the last two years, I've taught myself to program in order to
build my startup [LinerNotes.com](http://www.linernotes.com). I
started out expecting that the hardest part would be getting my head
around the sophisticated algorithmic logic of programming. To my
surprise, I've actually had

to do very little algorithmic work (Python has existing
libraries that implement nearly any algorithm better than I could.)

Instead, the hardest part has been getting my proficient at using the
*many* different tools in the programmer's utility belt. From emacs to
gunicorn, building a real project requires dozens of different
tools. Theoretically, one can *a priori* reason through a red-black
tree. But there's just no way to learn emacs without the reading the
manual. LinerNotes is actually a lot more complicated under the hood
than it is on the surface, so I've had to read quite a lot of
manuals. The point of this guide is to save you some of that trouble.

Struggling to write an API builds programming acumen. Struggling to
configure nginx is just a waste of time. I've found many partial
guides to parts of Django deployment but haven't found any single,
recently updated resource that lays out the **simple, Pythonic way of
deploying a Django site in production**.

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

![Architecture Diagram](https://raw.github.com/rogueleaderr/LinerNotes-site/master/LinerNotes/documentation/architecture_diagram.png?login=rogueleaderr&token=b453c4566dca05e61e5f10f22136d2c2)

##Set Up the "Physical" Servers

Since this guide is trying to get you to an actual publicly accessible site,
we're going to go ahead and build our site on an Amazon Elastic Compute Cloud
(EC2) "micro" instance (which is essentially free). Alternatively, you can use
[Vagrant](http://www.vagrantup.com/) to create a VM on your local computer.

For this tutorial, you'll need an existing EC2 account. There are [many tutorials on setting up an account](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/get-set-up-for-amazon-ec2.html) so I'm not going to walk you through it.

Amazon just released an integrated commandline tool that makes it easy to
administer all of their services, so we're going to use that to launch our servers.

The servers are:


This diagram describes how the key services for the app are spread over the servers:


##Install and Configure Your Services

##Deploy Your Code

##Set Up Monitoring

##Go Hard

**Gunicorn**: The main webserver program that executes LinerNotes' Django code.

**Celery**:   An async task system for Python. Also used for ghetto concurrency.

**Supervisor**: A process manager that attempts to make sure that all key services stay
  alive and are automatically restarted if they die for any reason.
  
**Nginx**: The proxy server. Routes incoming HTTP traffic to Gunicorn (or if Gunicorn is
  down, to an error page.)
  
**RabbitMQ**: A queue/message broker that handles asynchronous tasks created through Celery
  
**Memcached**: A simple in-memory key/value caching system.

**Postgres**: The main database server. Has three "logical" databases containing
  different types of data.
  
**ElaticSearch**: The search server. Communicates with webserver through REST interface.

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

Using the Amazon AWS Console
-----

Amazon provides a service called *IAM* that lets me create individual user accounts to log
into my AWS account with specifically controlled permissions. I have created an account
for you that lets you control my AWS resources with full permissions (except for billing /
editing permissions).

* Your username is "Carter_S"
* Your password can be found in [this file](https://www.dropbox.com/s/u7mrcch6wruc938/carter-aws-password.csv).
* Your API credentials (which you probably won't need)
[are here](https://www.dropbox.com/s/b0siokvfqlotmaa/carter_aws_credentials.csv).

If you need to login to AWS, use this link:
[https://linernotes.signin.aws.amazon.com/console](https://linernotes.signin.aws.amazon.com/console)

(You should only ever need to login to my AWS console if shit has *really* hit the fan.)

From the AWS console, you can access the EC2 tab that lets you control the virtual
servers, launch new servers from images, or [attach Elastic IP's](https://console.aws.amazon.com/ec2/home?region=us-east-1#s=Addresses).

You can also access [the S3 tab](https://console.aws.amazon.com/s3/home?region=us-east-1#) that lets you manipulate any my stored static files if
anything goes wrong with those. (More below).

The Code Base
---------

All of the website code lives
[on Github in my repo](https://github.com/rogueleaderr/hello-site).

I added you as a collaborator so you can pull/push as needed. I **very much** hope you
will not need to modify any code (if it comes to that, try to notify me at burning man and
I'll see if I can go back to Reno and do it myself.) But in an emergency, you can set up a
development environment most easily by creating a clone of the hello webserver from
the image and SSH'ing into it. You'll need to upload your SSH key, but there is a script
in the repo that will push any committed changes to the live production server:

    /var/www/hello-env/hello/hello/scripts/git_to_prod.sh

Supervisor should make sure that gunicorn and celery are running, so if you make code
changes you can just reset them as above and your changes will show up. You'll be able to
access the site live in a browser by visiting the "public DNS" for the server you start in AWS.

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
