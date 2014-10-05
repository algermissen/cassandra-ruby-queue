#!/usr/bin/env ruby
require 'cassandra'
require 'optparse'

host='127.0.0.1'
  outs message
keyspace='foo'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: observer.rb [options]"

  opts.on("-H", "--host HOST", "Cassandra host") { |h| host = h }
  opts.on("-K", "--keyspace KEYSPACE", "Keyspace to use") { |k| keyspace = k }
end.parse!

name='test'
queue = CassandraQueue.new(host,keyspace)

print "Showing Number-Of-Pending/Number-Of-Messages per shard\n\n"
print "Name Shard 0     Shard 1    Shard 2    Shard 3\n"
loop do
  count0a = queue.count_all(name,"0")
  count1a = queue.count_all(name,"1")
  count2a = queue.count_all(name,"2")
  count3a = queue.count_all(name,"3")

  count0d = queue.count_due(name,"0")
  count1d = queue.count_due(name,"1")
  count2d = queue.count_due(name,"2")
  count3d = queue.count_due(name,"3")

  printf "test %04d/%04d   %04d/%04d  %04d/%04d  %04d/%04d\r" , count0d,count0a,count1d,count1a,count2d,count2a,count3d,count3a
  sleep 1
end

