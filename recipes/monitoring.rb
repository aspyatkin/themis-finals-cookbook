id = 'themis-finals'

secret = ::ChefCookbook::Secret::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

netdata_basedir = '/opt/netdata'

netdata_install 'default' do
  install_method 'source'
  git_repository 'https://github.com/firehol/netdata.git'
  git_revision node[id]['monitoring']['netdata']['version']
  git_source_directory netdata_basedir
  autoupdate true
  update false
end

service 'netdata' do
  action :start
end

netdata_host = '127.0.0.1'
netdata_port = 19999

netdata_config 'global' do
  owner 'netdata'
  group 'netdata'
  configurations(
    'bind to' => netdata_host,
    'default port' => netdata_port,
    'history' => node[id]['monitoring']['netdata']['global']['history']
  )
end

netdata_python_plugin 'nginx' do
  owner 'netdata'
  group 'netdata'
  global_configuration(
    'retries' => 5,
    'update_every' => 2
  )
  jobs(
    'local' => {
      'url' => "http://127.0.0.1:#{node['nginx']['status']['port']}/nginx_status"
    }
  )
end

netdata_python_plugin 'redis' do
  owner 'netdata'
  group 'netdata'
  global_configuration(
    'retries' => 5,
    'update_every' => 2
  )
  jobs lazy {
    {
      'local' => {
        'host' => h.redis_host,
        'port' => h.redis_port,
        'pass' => secret.get(
          'redis:password',
          required: false,
          default: nil,
          prefix_fqdn: node[id]['redis_secret']['prefix_fqdn'].nil? ? node['secret']['prefix_fqdn'] : node[id]['redis_secret']['prefix_fqdn']
        )
      }
    }
  }
end

python_package 'psycopg2' do
  action :install
end

netdata_python_plugin 'postgres' do
  owner 'netdata'
  group 'netdata'
  global_configuration(
    'retries' => 5,
    'update_every' => 2
  )
  jobs lazy {
    {
      'local' => {
        'host' => h.postgres_host,
        'port' => h.postgres_port,
        'user' => node[id]['postgres']['username'],
        'password' => secret.get(
          "postgres:password:#{node[id]['postgres']['username']}",
          prefix_fqdn: node[id]['postgres_secret']['prefix_fqdn'].nil? ? node['secret']['prefix_fqdn'] : node[id]['postgres_secret']['prefix_fqdn']
        ),
        'database' => node[id]['postgres']['dbname']
      }
    }
  }
end

htpasswd_file = ::File.join(node['nginx']['dir'], '.netdata-htpasswd')
chef_gem 'htauth'

secret.get(
  'netdata:users',
  default: {},
  prefix_fqdn: node[id]['netdata_secret']['prefix_fqdn'].nil? ? node['secret']['prefix_fqdn'] : node[id]['netdata_secret']['prefix_fqdn']
).each do |username, password|
  htpasswd htpasswd_file do
    user username
    password password
    action :add
  end
end

fqdn = node[id]['monitoring']['fqdn']

nginx_vhost_template_vars = {
  fqdn: fqdn,
  htpasswd_file: htpasswd_file,
  netdata_host: netdata_host,
  netdata_port: netdata_port,
  access_log: ::File.join(node['nginx']['log_dir'], 'netdata-access.log'),
  error_log: ::File.join(node['nginx']['log_dir'], 'netdata-error.log')
}

nginx_site 'netdata' do
  template 'netdata.nginx.conf.erb'
  variables nginx_vhost_template_vars
  action :enable
end
