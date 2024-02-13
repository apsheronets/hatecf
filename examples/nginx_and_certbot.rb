#!/usr/bin/env ruby
require "hatecf"
target host: "123.123.123.123"
domain = "example.com"
email = "user@example.com"

nginx_http = <<~CONFIG
  server {
    listen      80;
    server_name #{domain};

    # The most important part:
    location /.well-known/acme-challenge {
      root /var/www/html/;
      try_files $uri $uri/ =404;
    }

    location / {
      return 301 https://#{domain}$request_uri;
    }
  }
CONFIG

nginx_https = <<~CONFIG
  server {
    listen      443 ssl;
    server_name #{domain};

    ssl_certificate     /etc/letsencrypt/live/#{domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/#{domain}/privkey.pem;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    location / {
      try_files $uri $uri/ =404;
    }
  }
CONFIG

apt_install "nginx certbot"

block do
  create_config "/etc/nginx/sites-available/#{domain}.http",  nginx_http
  create_config "/etc/nginx/sites-available/#{domain}.https", nginx_https

  ln_s "/etc/nginx/sites-available/#{domain}.http",
       "/etc/nginx/sites-enabled/#{domain}.http"

  check "certificate for #{domain} already exists" do
    File.exists? "/etc/letsencrypt/live/#{domain}/fullchain.pem"
  end.fix do
    # nginx won't start without certificate files missing
    rm("/etc/nginx/sites-enabled/#{domain}.https").afterwards do
      service_reload :nginx
    end
    command "certbot certonly -n --webroot --webroot-path=/var/www/html -m #{email} --agree-tos -d #{domain}"
  end

  ln_s "/etc/nginx/sites-available/#{domain}.https",
       "/etc/nginx/sites-enabled/#{domain}.https"
end.afterwards do
  service_reload "nginx"
end

edit_config "/etc/letsencrypt/cli.ini" do |c|
  c.add_line "deploy-hook = systemctl reload nginx"
end

perform!
