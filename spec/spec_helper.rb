Dir['./lib/*'].each do |file|
  next unless File.directory? file
  version = File.basename file
  $LOAD_PATH.unshift File.expand_path("../../lib/#{version}", __FILE__)
  require "udt_#{version}"
end
$LOAD_PATH.unshift File.expand_path("../control_classes", __FILE__)
require "client"
require "server"
require "tcp_control_client"
require "udp_client"
RSpec.configure do |c|
  c.fail_fast = true
end
