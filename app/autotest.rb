#!/usr/local/bin/ruby -w

require 'rubygems'

ERLC_FLAGS = "-Ideps +warn_unused_vars +warn_unused_import"

####
# SETUP
####

sourceDirs = ['src', 'src/chord', 'src/web']
sourceFiles = []

# Get a list of the source files
sourceDirs.each do |dir|
  sourceFiles = Dir.entries(dir).
      select {|name| name[-4...(name.length)] == ".erl"}
  sourceFiles.map! {|name| "#{dir}/#{name}"}
end

# Record when they were last modified
lastChanged = {}
sourceFiles.each do |fileName|
  lastChanged[fileName] = File.mtime(fileName)
end

####
# FUNCTIONALITY
####

def cleanBeams(sourceFiles)
  beamFiles = sourceFiles.map do |n| 
    "ebin/#{File.basename(n, ".erl")}.beam"
  end
  beamFiles.each do |beam|
    File.delete(beam)
  end
end

def compile(fileName)
  # Compile the file
  compile_output = `erlc -D TEST -pa ebin -Wall #{ERLC_FLAGS} -o ebin #{fileName}`
  
  # Remembers if there is an error or warning
  error = false

  compile_output.each_line do |line|
    case line
    when /.*Warning.*/
      print yellow(line)
    else
      print red(line)
      error = true
    end
  end
  
  error
end

def runTestOn(fileName)
  moduleName = File.basename(fileName, ".erl")
  test_output = `erl -noshell -pa ebin -eval 'eunit:test([{inparallel, #{moduleName}}], [verbose])' -s init stop`
  
  test_output.each_line do |line|
    case line
    when /= (EUnit) =/
      print line.gsub($1, green($1))
    when /\*failed\*/
      print red(line)
    when /(\.\.\..*ok)/
      print line.gsub($1,green($1))
    when /Failed:\s+(\d+)\.\s+Skipped:\s+(\d+)\.\s+Passed:\s+(\d+)\./
      puts "#{red("Failed: #{$1}")} Skipped: #{$2} #{green("Passed: #{$3}")}"
    when/(All \d+ tests passed.)/
      print green(line)
    else
      print line
    end
  end
end

def green(text)
  "\e[32m#{text}\e[0m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

def yellow(text)
  "\e[33m#{text}\e[0m"
end

####
# ACTUAL WORK
####

# Compile each file
anyErrors = false
sourceFiles.each do |fileName|
  anyErrors = compile(fileName) | anyErrors
end

# Run through all the tests
unless anyErrors
  puts "Starting testing loop"
  
  sourceFiles.each do |fileName|
    runTestOn(fileName)
  end

  trap 0, proc {
    puts "Terminating: #{$$}"
    
    # We end our session by cleaning away all the beam
    # files which contain the debugging info
    cleanBeams(sourceFiles)
  }
  
  # Main loop that checks if files have been changed
  while true do
    sleep 1
    sourceFiles.each do |fileName|
      lastChangedTime = File.mtime(fileName)
      if lastChanged[fileName] < lastChangedTime then
        runTestOn(fileName) if compile(fileName)
        lastChanged[fileName] = lastChangedTime
      end
    end
  end
else
  print red("Couldn't run tests because of errors or warnings.\n")
end
