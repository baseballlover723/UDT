require 'benchmark'
require_relative "spec/control_classes/client"
require_relative "spec/control_classes/server"
require_relative "spec/control_classes/udp_client"

def read_file(file_path, size)
  index = 0
  File.open(file_path, "rb") do |file|
    while (buffer = file.read(size)) do
      yield buffer, index
      index += 1
    end
  end
end

def read_file2(file_path, size)
  queue = Queue.new
  File.open(file_path, "rb") do |file|
    while (buffer = file.read(size)) do
      queue.push buffer
    end
  end
  index = 0
  until queue.empty?
    yield queue.pop, index
    index += 1
  end
end

Benchmark.bm do |x|
  x.report('send                 ') do
    udp = UDPClient.new('localhost', 3030)
    udp.send('spec/test_files/large.mp4')
  end

  # x.report('send and receive       ') do
  #   udp = UDPClient.new('localhost', 3030)
  #   udp.send('spec/test_files/large.mp4')
  #   received_data = udp.receive
  #   received_data.inspect
  # end

  x.report('send and receive fork') do
    udp = UDPClient.new('localhost', 3030)
    received_data = nil
    fork do
      received_data = udp.receive
    end
    udp.send('spec/test_files/large.mp4')
    Process.wait
    received_data.inspect
  end

  x.report('mod_test               ') do
    file_name = 'large.mp4'
    recieved_data = nil
    client, thread = nil
    Benchmark.measure do
      client = UDPClient.new 'localhost', 3030
      fork do
        recieved_data = client.receive
        File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) } if recieved_data
      end
    end.real
    sleep 0.01
    Benchmark.measure do
      client.send('spec/test_files/' + file_name)
      Process.wait
    end.real
  end
end

# # read, write = IO.pipe
# fork do
#   puts "In create fork block #{Process.pid}"
#   5.times do
#     sleep 1
#     puts "still alive"
#   end
#   puts 'done'
#   # write.write "Data is #{123}"
#   # write.close
# end
# # write.close
# # puts "the data is #{read.read}"
# Process.wait
# puts 'after wait'


