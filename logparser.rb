#!/usr/bin/env ruby

require 'csv'

# This is a utility that parses log files
# from the friend search dht network

class Request
  # Bins the requests by a 10th of a second
  def self.bin_and_sort(requests)
    bins = {}
    requests.each do |request|
      bin = request.start_time / 100
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

        type = record[1]
        case type
        when "start"
          @control_messages << {:start => control_msg_for_rec(record)}
        when "done"
          last_msg = @control_messages.pop
          last_msg[:end] = control_msg_for_rec(record)
          @control_messages << last_msg
        end

      when "data"
        # data;state;bits;time
        # data;lookup;bits;key;time
        if record[1] == "lookup" then
          add_to_request(record[3], record) 
        end
        @total_bandwidth += record[2].to_i

      when "act"
        # act;key;time;nodeId;action_type
        add_to_request(record[1], record)

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
    # Get the control messages
    run1 = data_for_control_message(@control_messages[0])
    run2 = data_for_control_message(@control_messages[1])
    run3 = data_for_control_message(@control_messages[2])
    run4 = data_for_control_message(@control_messages[3])

    header_lat = "ms;"
        "R1Lat;R1LatStDev;R1DataPoints;" +
        "R2Lat;R2LatStDev;R2DataPoints;" +
        "R3Lat;R3LatStDev;R3DataPoints;" +
        "R4Lat;R4LatStDev;R4DataPoints;" +
        "\n"
    header_nodes = "ms;"
        "R1Nodes;R1NodesStDev;R1DataPoints;" +
        "R2Nodes;R2NodesStDev;R2DataPoints;" +
        "R3Nodes;R3NodesStDev;R3DataPoints;" +
        "R4Nodes;R4NodesStDev;R4DataPoints;" +
        "\n"
    header_data = "ms;"
        "R1Data;R1DataStDev;R1DataPoints;" +
        "R2Data;R2DataStDev;R2DataPoints;" +
        "R3Data;R3DataStDev;R3DataPoints;" +
        "R4Data;R4DataStDev;R4DataPoints;" +
        "\n"
    yield header_lat, header_nodes, header_data

    0.upto(max_length_run(run1, run2, run3, run4)) { |n|
      lat = val_for(run1, n, :lat) + val_for(run2, n, :lat) + val_for(run3, n, :lat) + val_for(run4, n, :lat) + "\n"
      nodes = val_for(run1, n, :nodes) + val_for(run2, n, :nodes) + val_for(run3, n, :nodes) + val_for(run4, n, :nodes) + "\n"
      data = val_for(run1, n, :data) + val_for(run2, n, :data) + val_for(run3, n, :data) + val_for(run4, n, :data) + "\n"
      yield lat, nodes, data
    }
  end
  
  def val_for(run, n, what)
    av = 0
    stdev = 0
    num_datapoints = 0
    if run.size > n then
      values = run[n].map {|r| r.send(what)} 
      av = average_value(values)
      stdev = standard_deviation(values)
      num_datapoints = values.size
    end
    "#{av};#{stdev};#{num_datapoints};"
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

  def data_for_control_message(cm)
    requests = request_array_for_interval(cm[:start][:time], cm[:end][:time])
    Request.bin_and_sort(requests)
  end

  def control_msg_for_rec(rec)
    {:time => rec[2].to_i, :hosts => rec[3].to_i, :nodes => rec[4].to_i}
  end

  def add_to_request(key, data)
    request = @requests[key] ||= Request.new(key)
    request.add_data data
    @requests[key] = request
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
