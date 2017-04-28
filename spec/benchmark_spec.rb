require 'spec_helper'
require 'active_support'
require 'active_support/number_helper'
require 'benchmark'
require 'axlsx'

ActiveSupport::Deprecation.silenced = true
class Host
  attr_accessor :name, :address

  def initialize(name, address)
    @name = name
    @address = address
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
  attr_accessor :host, :file_name, :file_size, :udp_time, :tcp_time, :udt_time, :udp_loss, :tcp_loss, :udt_loss

  def initialize(host, file)
    @host = host
    @file_name = File.basename(file)
    @file_size = file.size
  end
end

PORT = 3030
HOSTS = [Host.new('Local', 'localhost'), Host.new('LAN', 'overmind.party'), Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
FILES = [File.new('spec/test_files/small.txt'), File.new('spec/test_files/medium.jpg')]
PROTOCOLS = [Protocol.new('tcp', TCPControlServer, TCPControlClient), Protocol.new('udp', UDPServer, UDPClient)]

def size(numb)
  ActiveSupport::NumberHelper.number_to_human_size(numb, {precision: 4, strip_insignificant_zeros: false})
end

def update_time(results, close=false)
  p = Axlsx::Package.new
  p.use_shared_strings = true

  p.workbook do |wb|
    styles = wb.styles
    title = styles.add_style :sz => 15, :b => true, :u => true
    center = styles.add_style :sz => 15, :b => true, :u => true, :alignment => {:horizontal => :center}
    default = styles.add_style :border => Axlsx::STYLE_THIN_BORDER, :alignment => {:horizontal => :center}

    wb.add_worksheet(name: 'Benchmark results') do |ws|
      ws.add_row ['', '', 'Time (sec)', '', '', 'Packet Loss', '', ''], style: center
      ws.merge_cells ws.rows.first.cells[(2..4)]
      ws.merge_cells ws.rows.first.cells[(5..7)]
      ws.add_row ['Host', 'File', 'UDP', 'TCP', 'UDT', 'UDP', 'TCP', 'UDT'], style: title
      results.each do |host, files|
        host
        files.values.each do |result|
          widths = [10, 20, 9, 9, 9, 9, 9, 9]
          ws.add_row [host.name, "#{result.file_name} (#{size result.file_size})", result.udp_time, result.tcp_time, result.udt_time, result.udp_loss, result.tcp_loss, result.udt_loss], widths: widths
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
  it 'sends and receives a file through aws with tcp' do
    client = TCPControlClient.new 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com', 3030
    file_name = 'medium.jpg'
    client.send('spec/test_files/' + file_name)
    f = client.receive
    File.open('spec/received_files/' + file_name, 'w') { |file| file.write(f) }

    expect(FileUtils.identical?('spec/test_files/' + file_name, 'spec/received_files/' + file_name)).to be_truthy, 'received file is different than sent file'
  end

  results = {}

  HOSTS.each do |host|
    context "Host: #{host.name}" do
      FILES.each do |file|
        context "File: #{File.basename(file)} (#{size file.size})" do
          PROTOCOLS.each do |protocol|
            context "Protocol: #{protocol.name}" do
              it 'correctly sends the file' do
                time = Benchmark.measure do
                  sleep rand
                end
                results[host] = {} unless results.has_key? host
                results[host][file.path] = Result.new(host, file) unless results[host].has_key? file.path
                result = results[host][file.path]
                result.send(protocol.name + "_time=", time.real)
                update_time results
              end
            end
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
