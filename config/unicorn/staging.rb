# ------------------------------------------------------------------------------
# Sample rails 3 config
# ------------------------------------------------------------------------------

# Set your full path to application.
app_path = "/srv/rails/hydrant-test/current"

# Set unicorn options
worker_processes 2
preload_app true
timeout 180
listen "0.0.0.0:3000"

# Spawn unicorn master worker for user apps (group: apps)
user 'vov', 'vov' 

# Fill path to your app
working_directory app_path

# Should be 'staging' by default, otherwise use other env 
rails_env = ENV['RAILS_ENV'] || 'staging'

# Log everything to one file
stderr_path "log/unicorn.log"
stdout_path "log/unicorn.log"

# Set master PID location
pid "#{app_path}/tmp/pids/unicorn.pid"

before_fork do |server, worker|
  ActiveRecord::Base.connection.disconnect!

  echo 'Stopping old Unicorn server gracefully'
  old_pid = "#{server.config[:pid]}.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  ActiveRecord::Base.establish_connection
end
