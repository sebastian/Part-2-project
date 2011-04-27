#!/usr/bin/env ruby

require 'csv'

# This parser parses log files of a particular type:
# Logfiles for runs where everything is fixed over a given time
# interval. The number of hosts and nodes and rate is fixed,
# and the experiment is run for a particular amount of time.

class Request
  attr_reader :start_time, :latency
  def initialize(data)
    items = data.chomp.split(" ")
    @start_time = items[0].to_i
    @latency = items[1].to_i
  end
end

class LogParser
  def initialize(dht, node_count, rate, number_of_runs) 
    @num_requests = 0
    @requests = []
    @dht = dht
    @node_count = node_count.to_i
    @rate = rate.to_i
    @number_of_runs = number_of_runs.to_i
  end

  def analyze
    # The CSV reader runs into problems with my data at times
    filename = "#{@dht}#{@node_count}hosts_rate#{@rate}"
    print "run: "
    1.upto(@number_of_runs) do |run|
      print "#{run} "
      File.open("output/run#{run}/#{filename}/latency_against_time.csv", 'r') do |file|
        file.gets # discard the line with the header
        while line = file.gets
          @requests << Request.new(line)
        end
      end
      File.open("output/run#{run}/#{filename}/num_requests.txt", 'r') do |file|
        @num_requests += file.gets.chomp.to_i
      end
    end
    print ". Total requests: #{@requests.length}\n"

    ##########################
    # output findings
    ##########################

    # Create a directory for the result, if it doesn't already exist
    dir_name = "output/summary/#{filename}"
    Dir.mkdir(dir_name) unless File.directory?(dir_name)

    total_num_req = @num_requests
    File.open("#{dir_name}/meta_data.txt", "w") do |file|
      num_good_req = @requests.size
      num_bad_req = total_num_req - num_good_req

      file.write "Experimental stats:\n"
      file.write "-------------------\n"
      file.write "samples:        #{total_num_req}\n"
      file.write "good samples:   #{num_good_req}\n"
      file.write "bad samples:    #{num_bad_req}\n"
      file.write "success ratio:  #{num_good_req / total_num_req.to_f}\n"

      file.write "\nOf all the good samples\n"
      file.write "-------------------\n"
      req_vals = @requests.map {|r| r.latency }
      sample_average = average_value(req_vals)
      sample_standard_deviation = standard_deviation(req_vals)
			sample_size = req_vals.size
      # To 95% confidence
			confidence = 0
      confidence = 1.96 * sample_standard_deviation / Math.sqrt(sample_size) if sample_size > 0
      file.write "Sample size:    #{sample_size}\n"
      file.write "Sample average: #{sample_average}\n"
      file.write "Sample stdev:   #{sample_standard_deviation}\n"
      file.write "95% conf pm:    #{confidence}\n"
    end

    # Write the cummulative distribution function for the successful requests
    # over time
    File.open("#{dir_name}/cdf.csv", "w") do |file|
      num_reqs = total_num_req.to_f # I am using the total number, so I can see the failure rate
      # Sorted by latency
      sorted_requests = @requests.sort { |a,b| a.latency <=> b.latency }

      current_interval = 0
      max_range = 10 # 10 ms
      accumulated_successes = 0

      file.write "# Time Ratio\n"
      file.write "0 0"

      sorted_requests.each do |request|
        if request.latency > current_interval + max_range
          file.write "#{current_interval} #{accumulated_successes / num_reqs}\n"
          current_interval += max_range
        end
        accumulated_successes += 1
      end

      # Write the same value up until the end of time
      current_value = accumulated_successes / num_reqs
      while current_interval < 5000
        file.write "#{current_interval} #{current_value}\n"
        current_interval += max_range
      end
    end

    temp_gnufile = "#{dir_name}/temp_gnuplot_cdf.gp"
    File.open(temp_gnufile, "w") do |gnuplot|
      gnuplot.write "set terminal postscript\n"
      gnuplot.write "set output '#{dir_name}/cdf.eps'\n"
      gnuplot.write "set xtics ('0' 0, '1' 1000, '2' 2000, '3' 3000, '4' 4000, '5' 5000)\n"
      gnuplot.write "set xlabel 'Latency /s'\n"
      gnuplot.write "set xrange [ 0 : 5000 ]\n"
      gnuplot.write "set ylabel 'Probability of having succeeded'\n"
      gnuplot.write "set title \"CDF for successful requests against latency\"\n"
      gnuplot.write "plot '#{dir_name}/cdf.csv' using 1:2 t '' with lines\n"
    end
    `gnuplot #{temp_gnufile}`
    File.delete(temp_gnufile)
  end

  private
  def average_value(values)
    sum = 0
    values.each do |value|
      sum += value
    end
    return sum / values.size if values.size > 1
    0
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
    return s / (n-1) if n > 1
    return s
  end
     
  # calculate the standard deviation of a population
  # accepts: an array, the population
  # returns: the standard deviation
  def standard_deviation(population)
    Math.sqrt(variance(population))
  end
end

if ARGV.size != 4 then
  puts "Please supply the Dht type, Node count and Rate you want to analyse together with the number of runs you have"
  exit 1
end

dht = ARGV[0]
node_count = ARGV[1]
rate = ARGV[2]
number_of_runs = ARGV[3]

LogParser.new(dht, node_count, rate, number_of_runs).analyze
