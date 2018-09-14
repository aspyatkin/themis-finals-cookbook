id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

url_repository = "https://github.com/#{node[id]['visualization']['github_repository']}"

directory h.visualization_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with?('development')
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  url_repository = "git@github.com:#{node[id]['visualization']['github_repository']}.git"
end

git2 h.visualization_dir do
  url url_repository
  branch node[id]['visualization']['revision']
  user instance.user
  group instance.group
  action :create
end

if node.chef_environment.start_with?('development')
  git_data_bag_item = nil
  begin
    git_data_bag_item = data_bag_item('git', node.chef_environment)
  rescue
    ::Chef::Log.warn('Check whether git data bag exists!')
  end

  git_options = git_data_bag_item.nil? ? {} : git_data_bag_item.to_hash.fetch('config', {})

  git_options.each do |key, value|
    git_config "git-config #{key} at #{h.visualization_dir}" do
      key key
      value value
      scope 'local'
      path h.visualization_dir
      user instance.user
      action :set
    end
  end
end
