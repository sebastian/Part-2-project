#!/usr/bin/env ruby

require 'csv'

# This is a utility that parses log files
# from the friend search dht network

class Request
  # Bins the requests by a 10th of a second
  def self.bin_and_sort(requests)
    bins = {}
    requests.each do |request|
      bin = request.start_time / 10000
      bins[bin] = [] unless bins[bin]
      bins[bin] << request
    end
    bins.to_a.sort.map {|b,r| r}
  end

  def <=>(other_request)
    return 0 if self.start_time == other_request.start_time
    return -1 if self.start_time < other_request.start_time
    return 1
  end

  def initialize(key)
    @key = key
    @node_count = 0
    @start_time = 0
    @end_time = 0
    @data = 0
    @time_seen = nil
    @success = false
  end

  def add_data(data)
    type = data[0]

    case type
    when "data"
      # data;lookup;bits;key;time
      # data;success;key;time
      action = data[1]
      if action == "lookup" then
        @data += data[2].to_i
      elsif action == "success" then
        @success = true
      end

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

  def was_successful
    @success
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
        # data;success;key;time

        type = record[1]

        if type == "success" then
          key = record[2]
          time = record[3]
          add_to_request(key, time, record)
          # We don't want to add to the bandwidth,
          # so we quit at this point
        end

        if type == "lookup" then
          key = record[3]
          time = record[4]
          add_to_request(key, time, record) 
        end

        @total_bandwidth += record[2].to_i unless type == "success"

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
    rate = nil
    # For each rate we create a separate file
    File.open("#{filename}_against_rate.csv", "w") do |rate_file|
      rate_file.write "Rate  Latency LatencyStDev  NodeCount NodeCountStDev  Bandwidth BandwidthStDev\n"
      
      @control_messages.each do |control_message|
        # In case this is the last control message
        # then there is no data to collect
        break unless control_message[:end]

        unless rate then
          rate = 1
        else
          rate = rate * 2
        end

        requests = data_for_control_message(control_message).sort

        latencies = requests.map {|r| r.lat}
        average_latency = average_value(latencies).to_f
        latency_stdev = standard_deviation(latencies)

        nodes = requests.map {|r| r.nodes}
        average_nodes = average_value(nodes).to_f
        nodes_stdev = standard_deviation(nodes)

        data = requests.map {|r| r.data}
        average_data = average_value(data).to_f
        data_stdev = standard_deviation(data)

        rate_file.write "#{rate} #{average_latency}  #{latency_stdev}  #{average_nodes}  #{nodes_stdev}  #{average_data} #{data_stdev}\n"

        File.open("#{filename}_against_time_for_rate#{rate}.csv", "w") do |time_file|
          base_time = nil
          
          time_file.write "Time  Latency  LatencyChange NodeCount NodeCountChange Bandwidth\n"
          requests.each do |request|

            base_time = request.start_time unless base_time
            time = request.start_time - base_time

            time_file.write "#{time} #{request.lat} #{request.lat/average_latency} #{request.nodes} #{request.nodes/average_nodes} #{request.data}\n"
          end
        end
      end
    end
  end

  private
  def data_for_control_message(cm)
    request_array_for_interval(cm[:start][:time], cm[:end][:time])
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
      request.is_in_interval(start_time, end_time) and request.has_end_time and request.was_successful
    }.map {|key, request| request}
  end

  def average_value(values)
    sum = 0
    values.each do |value|
      sum += value
    end
    sum / values.size
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
    return s / (n-1)
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
