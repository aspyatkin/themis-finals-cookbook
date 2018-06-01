id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

include_recipe "themis-finals-utils::install_ruby"
include_recipe "#{id}::prerequisite_postgres"

directory node[id]['basedir'] do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

script_dir = ::File.join(node[id]['basedir'], 'script')

directory script_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

media_dir = ::File.join(node[id]['basedir'], 'media')

directory media_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

team_logo_dir = ::File.join(node[id]['basedir'], 'team_logo')

directory team_logo_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

customize_cookbook = node[id].fetch('customize_cookbook', nil)
unless customize_cookbook.nil?
  node[id].fetch('team_logo_files', {}).each do |name_, path_path|
    full_path = ::File.join(team_logo_dir, path_path)
    cookbook_file full_path do
      cookbook customize_cookbook
      source name_
      owner instance.user
      group instance.group
      mode 0644
      action :create
    end
  end
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

cleanup_script = ::File.join(script_dir, 'cleanup_logs')

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

archive_script = ::File.join(script_dir, 'archive_logs')

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
    frontend_basedir: ::File.join(node[id]['basedir'], 'frontend'),
    visualization_basedir: node[id]['basedir'],
    media_dir: media_dir,
    backend_server_processes: node[id]['backend']['server']['processes'],
    backend_server_port_range_start: \
      node[id]['backend']['server']['port_range_start'],
    stream_processes: node[id]['stream']['processes'],
    stream_port_range_start: node[id]['stream']['port_range_start'],
    internal_networks: node[id]['config']['internal_networks'],
    htpasswd: htpasswd_file,
    team_networks: node[id]['config']['teams'].values.map { |x| x['network'] },
    contest_title: node[id]['config']['contest']['title'],
    flag_info_req_limit_burst: node[id]['config']['api_req_limits']['flag_info']['burst'],
    flag_info_req_limit_nodelay: node[id]['config']['api_req_limits']['flag_info']['nodelay'],
    flag_submit_req_limit_burst: node[id]['config']['api_req_limits']['flag_submit']['burst'],
    flag_submit_req_limit_nodelay: node[id]['config']['api_req_limits']['flag_submit']['nodelay'],
    flag_js_nginx: flag_js_nginx
  )
  action :enable
end
