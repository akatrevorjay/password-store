#!/usr/bin/env ruby

# Copyright (C) 2012 Alex Sayers <alex.sayers@gmail.com>. All Rights Reserved.
# This file is licensed under the GPLv2+. Please see COPYING for more information.

# LastPass Importer
#
# Reads CSV files exported from LastPass and imports them into pass.

# Usage:
#
# Go to lastpass.com and sign in. Next click on your username in the top-right
# corner. In the drop-down meny that appears, click "Export". After filling in
# your details again, copy the text and save it somewhere on your disk. Make sure
# you copy the whole thing, and resist the temptation to "Save Page As" - the
# script doesn't like HTML.
#
# Fire up a terminal and run the script, passing the file you saved as an argument.
# It should look something like this:
#
#$ ./lastpass2pass.rb path/to/passwords_file.csv

require 'erb'
require 'smarter_csv'
require 'optparse'

# Parse flags
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] filename"

  FORCE = false
  opts.on("-f", "--force", "Overwrite existing records") { FORCE = true }
  DEFAULT_GROUP = "(none)"
  opts.on("-d", "--default GROUP", "Place uncategorised records into GROUP") { |group| DEFAULT_GROUP = group }
  opts.on("-h", "--help", "Display this screen") { puts opts; exit }

  opts.parse!
end

# Check for a filename
if ARGV.empty?
  puts optparse
  exit 0
end

# Get filename of csv file
filename = ARGV.join(" ")
puts "Reading '#{filename}'..."


TEMPLATE = <<-EOT
<%= @password %>
<% if @username -%>
login: <%= @username %>
<% end -%>
<% if @url == "http://sn" -%>
type: note
<% elsif @url -%>
url: <%= @url %>
<% end -%>
desc: <%= @grouping + ' / ' if @grouping %><%= @name %>
<% if @fav and @fav > 0 -%>
favorite: <%= @fav %>
<% end -%>
<% if @extra -%>

<%= @extra %>
<% end -%>
EOT

class Record
  include ERB::Util
  attr_accessor :url, :username, :password, :extra, :fav, :name, :grouping
  @@unnamed_incr = 0

  def initialize(h)
    @name, @url, @username, @password, @extra, @grouping, @fav = h[:name], h[:url], h[:username], h[:password], h[:extra], h[:grouping], h[:fav]
  end

  def filename
    s = ""
    s << @grouping.gsub(/\\/, '/') + "/" unless @grouping.nil? or @grouping.empty?

    if @name.nil?
      @name = 'Unnamed_%s' % @@unnamed_incr
      @@unnamed_incr += 1
    end
    s << @name

    s.gsub(/ /, "_").gsub(/'/, "")
  end

  def to_s()
    ERB.new(TEMPLATE, nil, '-').result(binding)
  end
end

# Extract individual records
records = []
file = File.open(filename, "r:bom|utf-8")
n = SmarterCSV.process(file, {:chunk_size => 2}) do |chunk|
  chunk.each do |h|
    h[:grouping] = DEFAULT_GROUP if h[:grouping].nil?
    r = Record.new(h)
    records << r
  end
  #puts chunk.inspect
end
file.close
puts "Records parsed: #{records.length}"

successful = 0
errors = []
records.each do |r|
  if File.exist?("#{r.filename}.gpg") and not FORCE
    puts "skipped #{r.filename}: already exists"
    next
  end
  print "Creating record #{r.filename}..."
  IO.popen("pass insert -m '#{r.filename}' >/dev/null", 'w') do |io|
    io.puts r
  end
  if $? == 0
    puts " done!"
    successful += 1
  else
    puts " error!"
    errors << r
  end
end
puts "#{successful} records successfully imported!"

if errors.length > 0
  puts "There were #{errors.length} errors:"
  errors.each { |e| print e.name + (e == errors.last ? ".\n" : ", ")}
  puts "These probably occurred because an identically-named record already existed, or because there were multiple entries with the same name in the csv file."
end
