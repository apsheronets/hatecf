Configuration management powered by hate
========================================

it is ansible but **no yaml** and **30 times faster**

Current status
--------------

* Only Debian was tested. That's all I use.
* It works surprisingly well, but lacks a lot of features.
* The interface will most likely be changed in the future.

Script example
--------------

That's Ruby:

```ruby
#!/usr/bin/env ruby
require "hatecf"

target host: "123.123.123.123"

# Setting up SSH the way I like it
edit_config "/etc/ssh/sshd_config" do |c|
  c.replace_or_add_line "PermitRootLogin no",
                        "PermitRootLogin yes"
  c.replace_or_add_line "PasswordAuthentication yes",
                        "PasswordAuthentication no"
end.afterwards do
  service_reload "ssh"
end

user = "john"
create_user user, create_home: true, shell: "/bin/bash"
authorize_ssh_key user: user, key: (local_file "~/.ssh/id_rsa.pub")

# a list of my favourite tools
apt_install %w(aptitude htop vim less iptraf-ng rsync nmap screen dnsutils mtr-tiny curl wget git psmisc strace)

# Regexp examples
edit_config "/etc/sysctl.conf" do |c|
  # I hate ipv6
  %w(net.ipv6.conf.all.disable_ipv6
     net.ipv6.conf.default.disable_ipv6
     net.ipv6.conf.lo.disable_ipv6
  ).each do |setting|
    c.replace_or_add_line /#{setting}.*/,
                          "#{setting} = 1"
  end
  c.replace_or_add_line /net.ipv4.tcp_keepalive_time.*/,
                        "net.ipv4.tcp_keepalive_time = 60"
  c.replace_or_add_line /net.ipv4.tcp_keepalive_intvl.*/,
                        "net.ipv4.tcp_keepalive_intvl = 10"
  c.replace_or_add_line /net.ipv4.tcp_keepalive_probes.*/,
                        "net.ipv4.tcp_keepalive_probes = 3"
end.afterwards do
  command "sysctl -p /etc/sysctl.conf"
end

# Block examples
block do
  # ipv6 requests are waste of time
  cp local_file("./disableipv6.conf"),
     "/etc/unbound/unbound.conf.d/disableipv6.conf"
  cp local_file("./unbound-munin.conf"),
     "/etc/unbound/unbound.conf.d/munin.conf"
end.afterwards do
  service_reload :unbound
end
create_config "/etc/resolv.conf", "nameserver 127.0.0.1"

block do
  %w(hits memory histogram).each do |kind|
    ln_s "/usr/share/munin/plugins/unbound_munin_",
         "/etc/munin/plugins/unbound_munin_#{kind}"
  end
  edit_config "/etc/munin/plugin-conf.d/munin-node" do |c|
    c.add_block <<~TEXT
      [unbound*]
      user root
      env.unbound_conf /etc/unbound/unbound.conf
      env.unbound_control /usr/sbin/unbound-control
    TEXT
  end
end.afterwards do
  service_restart "munin-node"
end

# "Execute as another user" block
as user do
  # you could use ~
  mkdir_p "~/myapp/config/"
  # you could use local paths relative to your script
  cp local_file("myapp/database.yml"), "~/myapp/config/database.yml"
end

perform!
```

More examples
-------------

 * [one-click https with nginx and certbot](examples/nginx_and_certbot.rb)

A minimal script
----------------

```ruby
#!/usr/bin/env ruby
require "hatecf"
target host: "123.123.123.123"
# your tasks go here...
perform!
```

Install
-------

    sudo apt-get install ruby-rubygems
    gem install hatecf

Run a script
------------

Just `chmod +x` and execute it via `./script.rb` or whatever you named it.

How to check a script
---------------------

There is a `--dry` option for a dry run. The script will change nothing.

Documentation
-------------

Not existant yet, sorry.

Philosophy
----------

 * Don't invent dumb names. The script is called "script", and so on.
 * Any idempotent action should be named like an action anyway. `create_user` creates user only if it doesn't exist, despite not being named `ensure_the_user_exists`.
 * Better just mimic Bash.
 * Better save as much of ability to write scripts in pure Ruby as possible.

Developing
----------

 * Since we don't rely on a Gemfile, I found the `RUBYLIB=` environment variable quite useful.

TODO
----

 * Multiple targets support, including targeting blocks. My tiny goal is to be able to set PostgreSQL replication with the tool.
 * A whole lot of everything. At the moment of the first push the whole tool took just 3 days of coding.

Licensing
---------

LGPL-3.0
