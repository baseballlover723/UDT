require "udt/version"
require 'socket'
require 'json'
require 'colorize'

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
  MAX_JSON_OVERHEAD = 200
  ACK_WAIT = 0.1

  def initialize(host, port, verbose=false)
    @verbose = verbose
    @host = host
    @port = port
    @tcp = TCPSocket.new(host, port)
    @udp = UDPSocket.new
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
    send_command(:start, @data.size)
    Thread.new do
      wait_command('ready')
      until @data.empty?
        start = Time.now
        @data.each do |index, data|
          send_data index
        end
        time = Time.now - start
        sleep_time = (ACK_WAIT / 1) - time
        sleep sleep_time if sleep_time > 0
      end
    end
    while true
      command = wait_command 'ack'
      case command[:name]
        when 'ack'
          command[:data].each do |data_index|
            @data.delete data_index
          end
          break if @data.empty?
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
      print "receiving data index: #{index.to_s.yellow}, data: '#{raw_data.cyan}'\n" if @verbose
      data[index] = raw_data
      acks << index
    end
    send_acks! acks
    thread.exit
    @local_hack.close if @host == 'localhost'
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

  def wait_command(name)
    # {name: '', data: {}}
    while true
      raw_command = @tcp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD, Socket::MSG_PEEK) || '' # werid multithreading json bug, sometimes is empty
      begin
        command = JSON.parse(raw_command, symbolize_names: true)
      rescue JSON::ParserError
        print "\n#{raw_command}\n"
        @tcp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD)
        next
      end
      if command[:name] == name
        print 'received command ' + raw_command + "\n" if @verbose
        @tcp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD)
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
  end

  def send_data(index)
    data = @data[index]
    encoded = encode_data index, data
    print "sending data index #{index.to_s.yellow}, data: '#{data.green}'\n" if @verbose
    @udp.send(encoded, 0, @host, @port)
    # sleep 0.10
  end

  def send_acks!(acks)
    return if acks.empty?
    send_command(:ack, acks.to_a)
    acks.clear
  end
end
