module Client
  def initialize(host, port)
    raise 'not implemented'
  end

  def send(file)
    raise 'not implemented'
  end

  def get_binary_chunks(string, size)
    Array.new(((string.length + size - 1) / size)) { |i| string.byteslice(i * size, size) }
  end


  def read_file(file_path, size)
    index = 0
    File.open(file_path, "rb") do |file|
      while (buffer = file.read(size)) do
        yield buffer, index
        index += 1
      end
    end
  end
end
