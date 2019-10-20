#!/usr/bin/env ruby

# FIXME: This is way overcomplicated.

#: Description: search each formula for match
#:
#: Usage: brew grep [options] <regex>
#: 
#: Special Options:
#:   --ignore-casks                    do not search Cask formulae
#:   --detect-search-command           show which search command will be used
#:   --list-search-commands            list supported search commands
#:   -h, --help                        show this usage message
#: 
#: All other options will be passed through to the search tool.
#: 
#: Environment:
#:   HOMEBREW_GREP_SEARCH_CMD    set the search tool to use

require "formula"

class BrewGrep
  class SearchCommandNotFound < StandardError; end

  class SearchCommand
    # Name of the search command to call. This must be overridden by all
    # subclasses.
    #
    # While paths are supported, you should generally only use the basename.
    #
    # @return [String] search command to call
    def self.command
      raise NotImplementedError
    end

    # Core set of arguments passed to the command. This must be overridden by
    # all subclasses.
    #
    # The arguments chosen should aim to be as consistent as possible with
    # the other implementations behavior. Namely:
    #
    # - Search recursively.
    # - Follow symlinks.
    # - Color output.
    # - Exclude the `.git` directory.
    # - Only search Ruby files.
    # - List file paths when provided the `-l` flag.
    #
    # @return [Array<String>] array of default arguments that will be passed
    #   to command
    def self.base_args
      raise NotImplementedError
    end

    # Array of arguments passed to the search command when you wish to ignore
    # casks. This must be overridden by all subclasses.
    #
    # @return [Array<String>] array of flags that will exclude directories
    #   named "Casks"
    def self.ignore_casks_args
      raise NotImplementedError
    end

    # Perform the search.
    #
    # @param path [String] the path to recursively search
    # @param args [Array<String>] arguments that will be passed to the search
    #   command after the base_args, including the search string
    # @param options [Hash] special search options
    # @return [nil] results printed directly to STDOUT
    def self.search(path, extra_args, options = {})
      args = base_args + extra_args
      if options[:ignore_casks]
        args += ignore_casks_args
      end
      cmd = [command] + args + [path.to_s]
      IO.popen(cmd) do |f|
        res = f.read
        unless res.empty?
          puts res
          # add extra newline separator unless just listing paths
          print "\n" unless args.include?("-l")
        end
      end
    end

    # @return [Boolean] whether the given command exists in our path
    def self.installed?
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']

      # If our path has a path separator in it, don't try to find search our
      # $PATH, just return whether it is an executable that exists at the
      # given location.
      if command.include?(File::PATH_SEPARATOR)
        exts.each do |ext|
          exe = File.join(path, "#{command}#{ext}")
          return true if File.executable?(exe) && !File.directory?(exe)
        end
        return false
      end

      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{command}#{ext}")
          return true if File.executable?(exe) && !File.directory?(exe)
        end
      end

      false
    end
  end

  class RipGrepSearch < SearchCommand
    def self.command
      "rg"
    end

    def self.base_args
      ['-t', 'ruby', '--follow', "--color=always", "--heading", "-g", "!spec"]
    end

    def self.ignore_casks_args
      ['-g', '!Casks']
    end
  end

  class AckSearch < SearchCommand
    def self.command
      "ack"
    end

    def self.base_args
      ['--color', '--ruby', '--follow', '--heading', '--break', '--ignore-dir', 'spec']
    end

    def self.ignore_casks_args
      ['--ignore-dir', 'Casks']
    end
  end

  # Arguments used here must work on both the GNU and BSD variants of grep.
  class PortableGrepSearch < SearchCommand
    def self.command
      "grep"
    end

    def self.base_args
      ['-E', '--color=always', '--exclude-dir=.git', '--include=*.rb', '-R', '-S', '--exclude-dir=spec']
    end

    def self.ignore_casks_args
      ['--exclude-dir=Casks']
    end
  end


  class SearchCommandFinder
    # Listed in order of preference.
    @search_commands = [
      RipGrepSearch,
      AckSearch,
      PortableGrepSearch
    ]

    def self.search_commands
      @search_commands
    end

    def self.search_command_names
      search_commands.map(&:command)
    end

    def self.installed_search_commands
      search_commands.select(&:installed?)
    end

    def self.find(name)
      unless search_command_names.include?(name)
        raise SearchCommandNotFound, "'#{name}' is not a supported search command"
      end

      installed_search_commands.detect { |c| c.command == name }.tap do |cmd|
        unless cmd.installed?
          raise SearchCommandNotFound, "'#{name}' is not installed"
        end
      end
    end

    # @return [String] a supported search command installed on this system.
    def self.autodetect
      available = installed_search_commands
      if available.empty?
        raise SearchCommandNotFound, "could not find a supported search tool. Please install any of: #{search_command_names.join(', ')}"
      end
      available.first
    end
  end

  def initialize(options = {})
    if options[:search_command]
      @search_command = SearchCommandFinder.find(options[:search_command])
    end
  end

  def search_command
    @search_command ||= SearchCommandFinder.autodetect
  end

  # @return [Array] of tap directories
  def tap_dirs
    Tap.to_a.map(&:path)
  end

  # Search all taps for a pattern
  # @param [Array] arguments to pass to the search command, including pattern
  # @param [Hash] options to pass to the search command class
  def search(args, options)
    tap_dirs.each do |path|
      search_command.search(path, args, options)
    end
  end
end

if ARGV.include?('--list-search-commands')
  puts BrewGrep::SearchCommandFinder.search_command_names
  exit
end

if ARGV.include?('--detect-search-command')
  begin
    if ENV['HOMEBREW_GREP_SEARCH_CMD']
      puts BrewGrep::SearchCommandFinder.find(ENV['HOMEBREW_GREP_SEARCH_CMD']).command
    else
      puts BrewGrep::SearchCommandFinder.autodetect.command
    end
  rescue BrewGrep::SearchCommandNotFound => e
    puts e.message
    exit 1
  end
  exit
end

if ARGV.empty?
  puts "For usage information, run: brew grep --help"
  exit
end

# These are the boolean-only flags we handle. The flags are stripped from the
# args so that the search commands do not fail from them.
brew_grep_flags = {
  ignore_casks: false
}

if ARGV.include?('--ignore-casks')
  brew_grep_flags[:ignore_casks] = true
end

search_args = ARGV - brew_grep_flags.keys.map { |o| "--" + o.to_s.tr('_', '-') }
grep = BrewGrep.new(search_command: ENV['HOMEBREW_GREP_SEARCH_CMD'])
grep.search(search_args, brew_grep_flags)
