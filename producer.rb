#!/usr/bin/env ruby
require 'cassandra'
require 'optparse'
require_relative 'queue'

host='127.0.0.1'
keyspace='foo'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: producer.rb [options]"

  opts.on("-H", "--host HOST", "Cassandra host") { |h| host = h }
  opts.on("-K", "--keyspace KEYSPACE", "Keyspace to use") { |k| keyspace = k }
end.parse!

name='test'
queue = CassandraQueue.new(host,keyspace)

i=0
loop do
  i += 1
  t = Time.now.round(0)
  t = t + 60 # make it due in the future
  message="Message #{i} to be run at #{t}"
  #puts message
  queue.put_message(name,t,message)
  sleep 0.1
end

