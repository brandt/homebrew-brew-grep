#!/usr/bin/env ruby

# Description: search each formula for match
#
# Author: brandt
#
# Usage:
#
#     brew grep <regex>
#
# Example:
#
#     brew grep 'foobar'
#

require "formula"

class BrewGrep
  # Base command and arguments to use to search each tap.
  # Listed in order of preference.
  # Pattern and path will be appended to form the full search command.
  SEARCH_CMDS = {
    "ack" => ['--color', '--ruby', '--follow', '--heading', '--break'],
    "grep" => ['-E', '--color=always', '--exclude-dir=.git', '--include=*.rb', '-R', '-S']
  }

  # @return [Array] base command to execute with initial args
  attr_reader :base_cmd

  def initialize
    @base_cmd = SEARCH_CMDS.detect { |e, a| [e, a] if command?(e) }
    if @base_cmd.nil?
      puts "Couldn't find supported search tool."
      puts "Supported tools: #{SEARCH_CMDS.keys.inspect}"
      exit 1
    end
    puts "Searching with: #{base_cmd.first}\n\n"
  end

  # @return [Array] of tap directories
  def tap_dirs
    Tap.map(&:path)
  end

  # Search all taps for a pattern
  # @param [Array] arguments to pass to the search command, including pattern
  def search(args)
    tap_dirs.each do |path|
      search_directory(args, path)
    end
  end

  # @param [String] name of the command to search for
  # @return [Boolean] whether the given command exists in our path
  def command?(name)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{name}#{ext}")
        return true if File.executable?(exe) && !File.directory?(exe)
      end
    end
    false
  end

  # Search directory for pattern, printing results to STDOUT
  # @param [Array] command args (including pattern) to search for
  # @param [String] path to search
  def search_directory(args, path)
    cmd = [base_cmd, args, path.to_s].flatten
    IO.popen(cmd) do |f|
      res = f.read
      unless res.empty?
        puts res
        # add extra newline separator unless just listing paths
        print "\n" unless args.include?("-l")
      end
    end
  end
end

if ARGV.empty?
  puts "Usage:\n\tbrew grep [-i] <regex>"
  exit 2
end

grep = BrewGrep.new
grep.search(ARGV)
