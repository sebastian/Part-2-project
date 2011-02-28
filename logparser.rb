#!/usr/bin/env ruby

require 'csv'

# This is a utility that parses log files
# from the friend search dht network

class Request
  # Bins the requests by a 10th of a second
  def self.bin_and_sort(requests)
    bins = {}
    requests.each do |request|
      bin = request.start_time / 1000
      bins[bin] = [] unless bins[bin]
      bins[bin] << request
    end
    bins.to_a.sort.map {|b,r| r}
  end

  def initialize(key)
    @key = key
    @node_count = 0
    @start_time = 0
    @end_time = 0
    @data = 0
    @time_seen = nil
  end

  def add_data(data)
    type = data[0]

    case type
    when "data"
      # data;lookup;bits;key;time
      @data += data[2].to_i
    when "act"
      # act;key;time;nodeId;action_type
      key = data[1]
      time = data[2].to_i
      node = data[3]
      action = data[4]
    
      @node_count += 1
      @start_time = time if action == "start_lookup"
      @end_time = time if action == "end_lookup"
    end

  end

  def start_time
    @start_time
  end

  def data
    @data
  end

  def lat
    @end_time - @start_time
  end

  def nodes
    @node_count
  end

  def to_s
    # Output in format
    #
    # Key; 
    # Time taken (latency); 
    # nodes involved;
    # bits required
    "#{@key};#{lat};#{@node_count};#{@data}\n"
  end

  def is_in_interval(interval_start, interval_end)
    interval_start < @start_time and @end_time < interval_end
  end

  def has_end_time
    @end_time != 0
  end
end

class LogParser
  def initialize(filename) 
    @requests = {}
    @filename = filename
    @control_messages = []
    @total_bandwidth = 0
  end

  def parse
    CSV.open(@filename, 'r', ';') do |record|

      case record[0]
      when "ctrl"
        # ctrl;start;time;host_count;node_count
        # ctrl;end;time;host_count;node_count
        # ctrl;increase_rate;time;host_count;node_count

        # We want to bin the data by rate
        # Each record, except the first and last, mark the end of one bin
        # and the beginning of the next.
        type = record[1]
        time = record[2].to_i

        # Update previous control record
        unless @control_messages.size == 0 then
          previous_control_message = @control_messages.pop
          previous_control_message[:end] = control_msg_for_rec(record)
          @control_messages << previous_control_message
        end
        
        # Add a new control record
        new_control_message = {:start => control_msg_for_rec(record)}
        @control_messages << new_control_message

      when "data"
        # data;state;bits;time
        # data;lookup;bits;key;time
        if record[1] == "lookup" then
          key = record[3]
          time = record[4]
          add_to_request(key, time, record) 
        end
        @total_bandwidth += record[2].to_i

      when "act"
        # act;key;time;nodeId;action_type
        key = record[1]
        time = record[2]
        add_to_request(key, time, record)

      end
    end

    puts "Parsed out #{@requests.size} requests. Total bandwidth used: #{@total_bandwidth}"
  end

  def output
    output_records {|content| print content}
  end

  def to_file(filename)
    File.open("#{filename}_data.csv", "w") do |data_file|
      File.open("#{filename}_lat.csv", "w") do |lat_file|
        File.open("#{filename}_nodes.csv", "w") do |node_file|
          output_records {|lat, nodes, data| 
            lat_file.write lat
            node_file.write nodes
            data_file.write data
          }
        end
      end
    end
  end

  private
  def output_records
    header_lat = "Rate	Time  " +
        "Latency	StDev	NumDataPoints	" +
        "\n"
    header_nodes = "Rate	Time  " +
        "Nodes	NodesStDev	NumDataPoints	" +
        "\n"
    header_data = "Rate	Time  " +
        "Bits	BitsStDev	NumDataPoints	" +
        "\n"
    yield header_lat, header_nodes, header_data

    rate = nil
    @control_messages.each do |control_message|
      # In case this is the last control message
      # then there is no data to collect
      break unless control_message[:end]

      unless rate then
        rate = 1
      else
        rate = rate * 2
      end

      data_items = data_for_control_message(control_message)
      
      data_items.each_index do |index|

        data = data_items[index]

        # Get values for the phase
        lat = "#{rate}	#{index} " + val_for(data, :lat) + "\n"
        nodes = "#{rate}	#{index}  " + val_for(data, :nodes) + "\n"
        data = "#{rate} #{index}  " + val_for(data, :data) + "\n"
        yield lat, nodes, data
      end
    end

  end
  
  def val_for(run, what)
    av = 0
    stdev = 0
    num_datapoints = 0
    if run.size > 0 then
      values = run.map {|r| r.send(what)} 
      av = average_value(values)
      stdev = standard_deviation(values)
      num_datapoints = values.size
    end
    "#{av}	#{stdev}	#{num_datapoints}	"
  end

  def average_value(values)
    sum = 0
    values.each do |value|
      sum += value
    end
    sum / values.size
  end

  def max_length_run(r1, r2, r3, r4)
    max(r1.size, max(r2.size, max(r3.size, r4.size)))
  end

  def max(a,b)
    a > b ? a : b
  end

  # Returns requests starting within the interval of the control message,
  # binned by seconds elapsed from the beginning of the control message.
  # The bins are sorted by increasing time.
  def data_for_control_message(cm)
    requests = request_array_for_interval(cm[:start][:time], cm[:end][:time])
    Request.bin_and_sort(requests)
  end

  def control_msg_for_rec(rec)
    {:time => rec[2].to_i, :hosts => rec[3].to_i, :nodes => rec[4].to_i}
  end

  def add_to_request(key, time, data)
    master_key = "#{key}#{time.to_i / 10000}"
    request = @requests[master_key] ||= Request.new(master_key)
    request.add_data data
    @requests[master_key] = request
  end

  def request_array_for_interval(start_time, end_time)
    @requests.to_a.select {|key, request| 
      request.is_in_interval(start_time, end_time) and request.has_end_time
    }.map {|key, request| request}
  end

  def variance(population)
    n = 0
    mean = 0.0
    s = 0.0
    population.each { |x|
      n = n + 1
      delta = x - mean
      mean = mean + (delta / n)
      s = s + delta * (x - mean)
    }
    # if you want to calculate std deviation
    # of a sample change this to "s / (n-1)"
    return s / n
  end
     
  # calculate the standard deviation of a population
  # accepts: an array, the population
  # returns: the standard deviation
  def standard_deviation(population)
    Math.sqrt(variance(population))
  end
end

if ARGV.size == 0 then
  puts "Please supply the name of the log file to parse"
  exit 1
end

filename = ARGV.first
logParser = LogParser.new(filename)
logParser.parse
if ARGV.size == 2 then
  outputFilename = ARGV[1]
  logParser.to_file(outputFilename)
else
  logParser.output
end
