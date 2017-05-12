require 'spec_helper'
require 'active_support'
require 'active_support/number_helper'
require 'benchmark'
require 'axlsx'

Thread.abort_on_exception = true
ActiveSupport::Deprecation.silenced = true

class Host
  attr_accessor :name, :address

  def initialize(name, address)
    @name = name
    @address = address
  end
end

class TestFile
  attr_accessor :iterations

  def initialize(file_path, iterations)
    @file = File.new(file_path)
    @iterations = iterations
  end

  def name
    File.basename @file
  end

  def size
    ActiveSupport::NumberHelper.number_to_human_size(@file.size, {precision: 4, strip_insignificant_zeros: false})
  end
end

class Protocol
  attr_accessor :name, :server, :client

  def initialize(name, server, client)
    @name = name
    @server = server
    @client = client
  end
end

class Result
  attr_accessor :host, :file, :udp_time, :tcp_time, :udt_time, :udp_loss, :tcp_loss, :udt_loss

  def initialize(host, file)
    @host = host
    @file = file
  end
end

PORT = 3030
HOSTS = [Host.new('Local', 'localhost'), Host.new('LAN', 'overmind.party'), Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
# HOSTS = [Host.new('Local', 'localhost')]
# HOSTS = [Host.new('LAN', 'overmind.party')]
# HOSTS = [Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
FILES = [TestFile.new('spec/test_files/tiny.txt', 5), TestFile.new('spec/test_files/small.jpg', 5), TestFile.new('spec/test_files/medium.png', 5)]
# FILES = [TestFile.new('spec/test_files/small.jpg', 10)]
# FILES = [TestFile.new('spec/test_files/tiny.txt', 10)]
# FILES = [TestFile.new('spec/test_files/medium.png', 5)]
PROTOCOLS = [Protocol.new('tcp', TCPControlClient, TCPControlClient), Protocol.new('udp', UDPClient, UDPClient)]

def update_time(results, close=false)
  p = Axlsx::Package.new
  p.use_shared_strings = true

  p.workbook do |wb|
    styles = wb.styles
    title = styles.add_style :sz => 15, :b => true, :u => true
    center = styles.add_style :sz => 15, :b => true, :u => true, :alignment => {:horizontal => :center}
    default = styles.add_style :border => Axlsx::STYLE_THIN_BORDER, :alignment => {:horizontal => :center}
    percent = styles.add_style(:format_code => '[GREEN]0.00%;-[RED]0.00%', :alignment=>{:horizontal => :left, indent: 1})

    wb.add_worksheet(name: 'Benchmark results') do |ws|
      ws.add_row ['', '', 'Avg Time (sec)', '', '', '% Faster', 'Packet Loss', '', ''], style: center
      ws.merge_cells ws.rows.first.cells[(2..4)]
      ws.merge_cells ws.rows.first.cells[(6..8)]
      ws.add_row ['Host', 'File', 'UDP', 'TCP', 'UDT', 'Than TCP', 'UDP', 'TCP', 'UDT'], style: title
      results.each do |host, files|
        host
        files.values.each do |result|
          widths = [10, 30, 10, 10, 10, 15, 9, 9, 9]
          percentage = 0
          percentage = (result.tcp_time / result.udt_time) - 1 if result.tcp_time && result.udt_time
          data = [host.name, "#{result.file.name} (#{result.file.size}) (#{result.file.iterations} times)", result.udp_time, result.tcp_time, result.udt_time, percentage ,result.udp_loss, result.tcp_loss, result.udt_loss]
          ws.add_row data, widths: widths, style: [nil, nil, nil, nil, nil, percent]
        end
        ws.add_row []

      end
    end
  end
  begin
    system('wmctrl -c libreoffice') and puts 'closing excel' or sleep 0.15 if close && File.exists?('.~lock.benchmark.xlsx#')
    p.serialize 'benchmark.xlsx'
  rescue
    if close && ENV['BASH_ON_UBUNTU_ON_WINDOWS']
      puts 'closing excel'
      system 'cmd.exe /c taskkill /IM excel.exe'
      sleep 0.05
      begin
        p.serialize 'benchmark.xlsx'
      rescue
        sleep 0.15
        p.serialize 'benchmark.xlsx'
      end
    end
  end
end

describe 'Benchmark' do
  def clear_files
    Dir['./spec/received_files/*'].each do |file|
      begin
        File.delete(file)
      rescue Errno::EIO
        sleep 0.1
        File.delete(file)
      end
    end
  end

  after(:each) do
    print "                         \r"
    sleep 5
  end

  results = {}
  ITERATION_SLEEP = 1.5

  HOSTS.each do |host|
    context "Host: #{host.name}" do
      FILES.each do |file|
        context "File: #{file.name} (#{file.size})" do
          it 'correctly sends the file using TCP' do
            file_name = file.name
            recieved_data = nil
            time = 0.0
            iterations = 0
            while iterations < file.iterations
              clear_files
              print "\rTCP iteration: #{iterations} / #{file.iterations}"
              client, thread = nil
              time1 = Benchmark.measure do
                client = TCPControlClient.new host.address, 3030
                thread = Thread.new do
                  recieved_data = client.receive
                end
              end.real
              sleep 0.001 until thread[:ready]
              time2 = Benchmark.measure do
                client.send('spec/test_files/' + file_name)
                thread.join
              end.real
              next unless recieved_data
              File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
              time += time1 + time2
              iterations += 1
              sleep ITERATION_SLEEP
              expect(FileUtils.identical?('spec/test_files/' + file_name, 'spec/received_files/' + file_name)).to be_truthy, 'received file is different than sent file'
            end

            results[host] = {} unless results.has_key? host
            results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
            result = results[host][file.name]
            result.tcp_time = time.real / file.iterations
            update_time results
            print "\r"
          end

          it 'correctly sends the file using UDP' do
            file_name = file.name
            recieved_data = nil
            time = 0.0
            iterations = 0
            while iterations < file.iterations
              clear_files
              print "\rUDP iterations: #{iterations} / #{file.iterations}"
              client, thread = nil
              time1 = Benchmark.measure do
                client = UDPClient.new host.address, 3030
                thread = Thread.new do
                  recieved_data = client.receive
                end
              end.real
              sleep 0.001 until thread[:ready]
              time2 = Benchmark.measure do
                client.send('spec/test_files/' + file_name)
                thread.join
              end.real
              next unless recieved_data
              time += time1 + time2
              iterations += 1
              File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
              expect(File.exist? 'spec/received_files/' + file_name).to be_truthy, 'did not create file'
              expect(File.zero? 'spec/received_files/' + file_name).to be_falsey, 'file is empty'
              sleep ITERATION_SLEEP
            end

            results[host] = {} unless results.has_key? host
            results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
            result = results[host][file.name]
            result.udp_time = (time.real - UDPClient::TIMEOUT * (file.iterations)) / (file.iterations)
            update_time results
            print "\r"
          end

          it 'correctly sends the file using UDT' do
            file_name = file.name
            recieved_data = nil
            time = 0.0
            iterations = 0
            while iterations < file.iterations
              clear_files
              print "\rUDT iteration: #{iterations} / #{file.iterations}"
              client, thread = nil
              time1 = Benchmark.measure do
                client = UDT.new host.address, 3030#, true
                thread = Thread.new do
                  recieved_data = client.receive
                end
              end.real
              sleep 0.001 until thread[:ready]
              time2 = Benchmark.measure do
                client.send('spec/test_files/' + file_name)
                thread.join
              end.real
              next unless recieved_data
              time += time1 + time2
              iterations += 1
              File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
              expect(FileUtils.identical?('spec/test_files/' + file_name, 'spec/received_files/' + file_name)).to be_truthy, 'received file is different than sent file'
              sleep ITERATION_SLEEP
            end

            results[host] = {} unless results.has_key? host
            results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
            result = results[host][file.name]
            result.udt_time = time.real / file.iterations
            update_time results
            print "\r"
          end
        end
      end
    end
  end

  after(:all) do
    update_time results, true
    file_to_open = "./benchmark.xlsx"
    puts 'opening excel'
    system ENV['BASH_ON_UBUNTU_ON_WINDOWS'] ? "cmd.exe /c start #{file_to_open}" : "nohup xdg-open #{file_to_open} &"
  end
end
