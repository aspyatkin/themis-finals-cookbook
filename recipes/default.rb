id = 'themis-finals'

include_recipe "#{id}::prerequisite_ruby"

include_recipe "#{id}::prerequisite_postgres"

directory node[id]['basedir'] do
  owner node[id]['user']
  group node[id]['group']
  mode 0755
  recursive true
  action :create
end

logs_basedir = ::File.join(node[id]['basedir'], 'logs')

directory logs_basedir do
  owner node[id]['user']
  group node[id]['group']
  mode 0755
  recursive true
  action :create
end

team_logo_dir = ::File.join(node[id]['basedir'], 'team_logo')

directory team_logo_dir do
  owner node[id]['user']
  group node[id]['group']
  mode 0755
  recursive true
  action :create
end

include_recipe "#{id}::sentry"
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

enable_livetunnel = \
  node[id].fetch('live', {}).fetch('enable', false) &&
  !node[id].fetch('live', {}).fetch('server_username', nil).nil? &&
  !node[id].fetch('live', {}).fetch('server_hostname', nil).nil? &&
  !node[id].fetch('live', {}).fetch('remote_port', nil).nil?

if enable_livetunnel
  all_programs << "#{namespace}.livetunnel"
end

supervisor_group namespace do
  programs all_programs
  action :enable
end

cleanup_script = ::File.join(node[id]['basedir'], 'cleanup_logs')

template cleanup_script do
  source 'cleanup_logs.sh.erb'
  owner node[id]['user']
  group node[id]['group']
  mode 0775
  variables(
    logs_basedir: logs_basedir,
    sentry_logs_basedir: ::File.join(node[id]['basedir'], 'sentry', 'logs')
  )
end

archive_script = ::File.join(node[id]['basedir'], 'archive_logs')

template archive_script do
  source 'archive_logs.sh.erb'
  owner node[id]['user']
  group node[id]['group']
  mode 0775
  variables(
    logs_basedir: logs_basedir,
    sentry_logs_basedir: ::File.join(node[id]['basedir'], 'sentry', 'logs')
  )
end

nginx_site 'themis-finals' do
  template 'nginx.conf.erb'
  variables(
    server_name: node[id]['fqdn'],
    live_server_name: node[id].fetch('live', {}).fetch('fqdn', nil),
    logs_basedir: logs_basedir,
    frontend_basedir: ::File.join(node[id]['basedir'], 'frontend'),
    visualization_basedir: node[id]['basedir'],
    backend_server_processes: node[id]['backend']['server']['processes'],
    backend_server_port_range_start: \
      node[id]['backend']['server']['port_range_start'],
    stream_processes: node[id]['stream']['processes'],
    stream_port_range_start: node[id]['stream']['port_range_start'],
    internal_networks: node[id]['config']['internal_networks'],
    team_networks: node[id]['config']['teams'].values.map { |x| x['network'] }
  )
  action :enable
end
