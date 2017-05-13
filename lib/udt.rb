require "udt/version"
require 'socket'
require 'json'
require 'colorize'
require 'thread'

class String
  def chunk(string, size)
    string.scan(/.{1,#{size}}/)
  end
end

class Set
  def to_s
    to_a.to_s
  end
end

class UDT
  PACKET_SIZE = 1024
  MAX_JSON_OVERHEAD = 20000
  ACK_WAIT = 0.25

  def initialize(host, port, verbose=false)
    @verbose = verbose
    @host = host
    @port = port
    @tcp = TCPSocket.new(host, port)
    @udp = UDPSocket.new
    @acks_mutex = Mutex.new

    if host == 'localhost'
      @local_hack = UDPSocket.new
      @local_hack.bind('localhost', @port)
    end
    print "\n" if @verbose
  end

  def send(file_path)
    @data = {}
    read_file file_path, PACKET_SIZE do |chunk, index|
      @data[index] = chunk
    end
    @congestion_control_sleep_time = ACK_WAIT * 100.0 / @data.size
    send_command(:start, @data.size)
    thread = Thread.new do
      wait_command('ready')
      @data.each do |index, data|
        send_data index
      end
      until @data.empty?
        @data.each do |index, data|
          send_data index
          sleep @congestion_control_sleep_time
        end
      end
    end
    while true
      command = wait_command 'ack'
      case command[:name]
        when 'ack'
          command[:data].each do |data_index|
            @data.delete data_index
          end
          @last_acks = command[:data].size
          @last_acks = 1 if @last_acks == 0
          @congestion_control_sleep_time = ACK_WAIT / 2.0 / @last_acks
          # print "packets to send: #{@data.size} last_acks: #{@last_acks} congestion_control_sleep_time: #{@congestion_control_sleep_time}\r"# if @verbose
          break if @data.empty?
        when 'fin'
          puts 'got fin, stopping sending'
          thread.exit
          break
      end
    end
  end

  def receive
    thread = Thread.current
    thread[:ready] = false
    Thread.new do
      sleep 0.01
      thread[:ready] = true
    end
    command = wait_command 'start'
    packets = command[:data]
    data = {}
    acks = Set.new
    send_command(:ready)
    thread = Thread.new do
      (@local_hack || @udp).wait_readable
      until data.size == packets
        sleep ACK_WAIT
        send_acks! acks
      end
    end
    until data.size == packets
      index, raw_data = wait_data
      # print "receiving data index: #{index.to_s.yellow}, data: '#{raw_data.cyan}'\n" if @verbose
      # print "receiving data index: #{index.to_s.yellow}, data: ''}'\n" if @verbose
      data[index] = raw_data
      @acks_mutex.synchronize do
        acks << index
      end
    end
    send_acks! acks
    thread.exit
    send_command(:fin)
    @local_hack.close if @host == 'localhost'
    @tcp.flush
    @tcp.close_write

    piece_together data
  end

  private

  def read_file(file_path, size)
    File.open(file_path, "rb") do |file|
      counter = 0
      while (buffer = file.read(size)) do
        yield buffer, counter
        counter += 1
      end
    end
  end

  def piece_together(data)
    data_string = ''
    for index in 0...data.size
      data_string << data[index]
    end
    data_string
  end

  def encode_data(index, raw_data)
    "#{index}|#{raw_data}"
  end

  def decode_data(encoded)
    decoded = encoded.partition '|'
    return decoded[0].to_i, decoded[2]
  end

  # don't use json
  def wait_command(name)
    # {name: '', data: {}}
    while true
      raw_command = @tcp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD, Socket::MSG_PEEK) || '""' # werid multithreading json bug, sometimes is empty
      index = raw_command.index('}')
      next unless index
      raw_command = raw_command[0..index] unless raw_command.size + 1 == index
      begin
        command = JSON.parse(raw_command, symbolize_names: true)
      rescue JSON::ParserError => e
        puts 'FAILED!!!!!!!!!!!!!!!!!!!'
      end
      # print 'check received command ' + raw_command + "\n" if @verbose
      if command[:name] == name
        print 'received command ' + raw_command + "\n" if @verbose
        @tcp.recv(raw_command.bytesize)
        return command
      end
    end
  end

  def wait_data
    udp = @local_hack || @udp
    decode_data udp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD)
  end

  def send_command(command, data=nil)
    json = JSON.generate({name: command, data: data})
    print "send command #{json}\n" if @verbose
    @tcp.send(json, 0)
    @tcp.flush
  end

  def send_data(index)
    data = @data[index]
    encoded = encode_data index, data
    # print "sending data index #{index.to_s.yellow}, data: '#{data.green}'\n" if @verbose
    # print "sending data index #{index.to_s.yellow}, data: ''\n" if @verbose
    @udp.send(encoded, 0, @host, @port)
    # sleep 0.001
  end

  def send_acks!(acks)
    @acks_mutex.synchronize do
      return if acks.empty? && @sent_empty_acks_last
      send_command(:ack, acks.to_a)
      @sent_empty_acks_last = acks.empty?
      acks.clear
    end
  end
end
