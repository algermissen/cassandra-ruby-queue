#!/usr/bin/env ruby
require 'cassandra'
require 'optparse'
require_relative 'queue'

host='127.0.0.1'
keyspace='foo'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: consumer.rb [options]"

  opts.on("-H", "--host HOST", "Cassandra host") { |h| host = h }
  opts.on("-K", "--keyspace KEYSPACE", "Keyspace to use") { |k| keyspace = k }
end.parse!

name='test'
queue = CassandraQueue.new(host,keyspace)

loop do
  message = queue.take_message(name)
  if(message)
    puts "MESSAGE: #{message}"
  end
  sleep 0.1
end

