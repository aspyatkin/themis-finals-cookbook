id = 'themis-finals'

default[id]['fqdn'] = nil
default[id]['extra_fqdn'] = []

default[id]['postgres']['dbname'] = 'themis-finals'
default[id]['postgres']['username'] = 'themis_finals_user'

default[id]['basedir'] = '/var/themis/finals'

default[id]['debug'] = false
default[id]['autostart'] = false

default[id]['backend']['github_repository'] = 'themis-project/themis-finals-backend'
default[id]['backend']['revision'] = 'master'
default[id]['backend']['queue']['redis_db'] = 1
default[id]['backend']['queue']['processes'] = 2
default[id]['backend']['server']['processes'] = 2
default[id]['backend']['server']['port_range_start'] = 3000

default[id]['frontend']['github_repository'] = 'themis-project/themis-finals-frontend'
default[id]['frontend']['revision'] = 'master'

default[id]['stream']['github_repository'] = 'themis-project/themis-finals-stream'
default[id]['stream']['revision'] = 'master'
default[id]['stream']['redis_db'] = 2
default[id]['stream']['redis_channel_namespace'] = 'themis.finals'
default[id]['stream']['port_range_start'] = 4000
default[id]['stream']['processes'] = 2

default[id]['visualization']['github_repository'] = 'themis-project/themis-finals-visualization'
default[id]['visualization']['revision'] = 'master'
