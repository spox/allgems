# This file is a simple hack to force hanna to use
# the 2.3.0 version of rdoc

if ARGV.size == 1 and ARGV.first == '-h'
  puts <<-HELP
Hanna -- a better RDoc template
Synopsis:
  hanna [options]  [file names...]
  [sudo] hanna --gems  [gem names...]

Example usage:

  hanna lib/**/*.rb

Hanna passes all arguments to RDoc. To find more about RDoc options, see
"rdoc -h". Default options are:

  -o doc --inline-source --charset=UTF-8

The second form, with the "--gems" argument, serves the same purpose as
the "gem rdoc" command: it generates documentation for installed gems.
When no gem names are given, "hanna --gems" will install docs for EACH of
the gems, which can, uh, take a little while.

HELP
  exit 0
end

unless RUBY_PLATFORM =~ /(:?mswin|mingw)/
  require 'pathname'
  hanna_dir = Pathname.new(__FILE__).realpath.dirname + '../lib'
else
  # windows
  hanna_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
end

$:.unshift(hanna_dir) unless $:.include?(hanna_dir)

require 'rubygems'

# and now for some magic to make this work
gem 'rdoc', '=2.3.0'
module Gem
    class << self
        alias :fubar :find_files
        remove_method :find_files
    end
end
require 'rdoc/rdoc'
module Gem
    class << self
        alias :find_files :fubar
        remove_method :fubar
    end
end

options = []

options << '-f' << 'html' << '-T' << 'hanna'
options << '--inline-source' << '--charset=UTF-8'

if ARGV.first == '--gems'
  require 'rubygems/doc_manager'
  Gem::DocManager.configured_args = options

  gem_names = ARGV.dup
  gem_names.shift

  unless gem_names.empty?
    specs = gem_names.inject([]) do |arr, name|
      found = Gem::SourceIndex.from_installed_gems.find_name(name)
      spec = found.sort_by {|s| s.version }.last
      arr << spec if spec
      arr
    end
  else
    specs = Gem::SourceIndex.from_installed_gems.inject({}) do |all, pair|
      full_name, spec = pair
      if spec.has_rdoc? and (!all[spec.name] or spec.version > all[spec.name].version)
        all[spec.name] = spec
      end
      all
    end
    specs = specs.values
    puts "Hanna is installing documentation for #{specs.size} gem#{specs.size > 1 ? 's' : ''} ..."
  end

  specs.each do |spec|
    Gem::DocManager.new(spec).generate_rdoc
  end
else
  options << '-o' << 'doc' unless ARGV.include?('-o') or ARGV.include?('--op')
  options.concat ARGV

  RDoc::RDoc.new.document(options)
end
