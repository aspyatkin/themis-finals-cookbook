id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

include_recipe "themis-finals-utils::install_ruby"
include_recipe "#{id}::prerequisite_postgres"
include_recipe 'graphicsmagick::default'
include_recipe 'graphicsmagick::devel'

directory node[id]['basedir'] do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

directory h.script_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

directory h.media_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

directory h.team_logo_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

include_recipe "#{id}::backend"
include_recipe "#{id}::frontend"
include_recipe "#{id}::stream"
include_recipe "#{id}::visualization"

namespace = "#{node[id]['supervisor_namespace']}.master"

all_programs = [
    "#{namespace}.stream",
    "#{namespace}.queue",
    "#{namespace}.scheduler",
    "#{namespace}.server"
]

supervisor_group namespace do
  programs all_programs
  action :enable
end

cleanup_script = ::File.join(h.script_dir, 'cleanup_logs')

template cleanup_script do
  source 'cleanup_logs.sh.erb'
  owner instance.user
  group instance.group
  mode 0775
  variables(
    dirs: [
      node['nginx']['log_dir'],
      node['supervisor']['log_dir']
    ]
  )
end

archive_script = ::File.join(h.script_dir, 'archive_logs')

template archive_script do
  source 'archive_logs.sh.erb'
  owner instance.user
  group instance.group
  mode 0775
  variables(
    dirs: [
      node['nginx']['log_dir'],
      node['supervisor']['log_dir']
    ]
  )
end

htpasswd_file = ::File.join(node['nginx']['dir'], "htpasswd_themis-finals")

htpasswd htpasswd_file do
  user secret.get('themis-finals:auth:master:username')
  password secret.get('themis-finals:auth:master:password')
  action :overwrite
end

ratelimit_nginx_conf = ::File.join(node['nginx']['dir'], 'conf.d', 'themis_finals_ratelimit.conf')

template ratelimit_nginx_conf do
  source 'ratelimit.nginx.conf.erb'
  owner 'root'
  group node['root_group']
  variables(
    team_networks: node[id]['config']['teams'].values.map { |x| x['network'] },
    flag_submit_req_limit_rate: node[id]['config']['api_req_limits']['flag_submit']['rate'],
    flag_info_req_limit_rate: node[id]['config']['api_req_limits']['flag_info']['rate'],
  )
  action :create
  notifies :restart, 'service[nginx]', :delayed
end

flag_js_nginx = ::File.join(node['nginx']['dir'], 'themis_finals_flag.js')

cookbook_file flag_js_nginx do
  source 'themis_finals_flag.js'
  owner 'root'
  group node['root_group']
  action :create
  notifies :restart, 'service[nginx]', :delayed
end

fqdn_list = [node[id]['fqdn']].concat(node[id]['extra_fqdn'])

nginx_site 'themis-finals' do
  template 'nginx.conf.erb'
  variables(
    fqdn_list: fqdn_list,
    debug: node[id]['debug'],
    access_log: ::File.join(node['nginx']['log_dir'], "themis-finals_access.log"),
    error_log: ::File.join(node['nginx']['log_dir'], "themis-finals_error.log"),
    frontend_basedir: h.frontend_dir,
    visualization_basedir: node[id]['basedir'],
    media_dir: h.media_dir,
    backend_server_processes: node[id]['backend']['server']['processes'],
    backend_server_port_range_start: \
      node[id]['backend']['server']['port_range_start'],
    stream_processes: node[id]['stream']['processes'],
    stream_port_range_start: node[id]['stream']['port_range_start'],
    internal_networks: node[id]['config']['internal_networks'],
    htpasswd: htpasswd_file,
    team_networks: node[id]['config']['teams'].values.map { |x| x['network'] },
    competition_title: node[id]['config']['competition']['title'],
    flag_info_req_limit_burst: node[id]['config']['api_req_limits']['flag_info']['burst'],
    flag_info_req_limit_nodelay: node[id]['config']['api_req_limits']['flag_info']['nodelay'],
    flag_submit_req_limit_burst: node[id]['config']['api_req_limits']['flag_submit']['burst'],
    flag_submit_req_limit_nodelay: node[id]['config']['api_req_limits']['flag_submit']['nodelay'],
    flag_js_nginx: flag_js_nginx
  )
  action :enable
end

template '/usr/local/bin/themis-final-cli' do
  source 'themis-final-cli.sh.erb'
  user instance.root
  group node['root_group']
  mode 0755
  variables(
    backend_dir: h.backend_dir
  )
  action :create
end

directory h.domain_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

node[id]['config']['domain_files'].each do |item|
  domain_filename = ::File.join(h.domain_dir, "#{item['name']}.rb")
  domain_vars = {
    services: item['services']
  }

  if item['type'] == 'competition_init'
    domain_vars.merge!({
      internal_networks: node[id]['config']['internal_networks'],
      settings: node[id]['config']['settings'],
      deprecated_settings: node[id]['config']['deprecated_settings'],
      teams: node[id]['config']['teams']
    })
  end

  template domain_filename do
    source "#{item['type']}.rb.erb"
    user instance.user
    group instance.group
    mode 0644
    variables domain_vars
    action :create
  end
end
