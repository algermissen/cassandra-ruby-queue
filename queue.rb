require 'cassandra'
require 'logger'

class CassandraQueue

  def initialize(host, keyspace)
    # Must not be less than 4 to ensure one shard 'space' to handle
    # up to 60 seconds of clock skew
    @number_of_shards = 4

    @host = host
    @keyspace = keyspace

    @logger = Logger.new(STDERR)
    @logger.level = Logger::DEBUG

    @cluster = Cassandra.connect(hosts: [@host],consistency: :quorum)
    @session = @cluster.connect(keyspace)

    @logger.info("Cassandra connection established and got session")

    @session.execute(<<-CREATETABLE
      create table if not exists queue (
        name text,
        shard text,
        lock text static,  
        due timestamp,
        id timeuuid,
        message text,
        primary key ((name,shard),due,id)
     )
     with clustering order by (due asc, id asc)
      and gc_grace_seconds = 60
    CREATETABLE
    )

    @put_stmt = @session.prepare("insert into queue (name,shard,due,id,message) values (?,?,?,now(),?) ")
    @get_stmt = @session.prepare("select due,id,message from queue where name = ? and shard = ? and due < dateOf(now()) limit 1")
    @delete_stmt = @session.prepare("delete from queue where name = ? and shard = ? and due = ? and id = ?")

    @count_due_stmt = @session.prepare("select count(*) from queue where name = ? and shard = ? and due < dateOf(now())")
    @count_all_stmt = @session.prepare("select count(*) from queue where name = ? and shard = ?")

  end

  

  def put_message(name,due,message)
    mts = minute_timestamp_from_producer_clock
    shard = calc_producer_shard(mts)
    @logger.debug("Putting message in #{name}, shard #{shard}")
    
    begin
      @session.execute(@put_stmt, name, shard.to_s, due, message)
    rescue StandardError => e
      @logger.error("StandardError occurred, unable to put: #{e}")
      return false
    end
    return true
  end

  def count_all(name,shard)
    begin
      @session.execute(@count_all_stmt, name, shard.to_s).each do |row|
        return row['count']
      end
    rescue StandardError => e
      @logger.error("StandardError occurred, unable to read count all: #{e}")
      return -1
    end
  end

  def count_due(name,shard)
    begin
      @session.execute(@count_due_stmt, name, shard.to_s).each do |row|
        return row['count']
      end
    rescue StandardError => e
      @logger.error("StandardError occurred, unable to read count due: #{e}")
      return -1
    end
  end

  def take_message(name)
    mts = minute_timestamp_from_consumer_clock
    shard = calc_consumer_shard(mts)
    @logger.debug("Trying to take one message from #{name}, shard #{shard}")
    due,id,message = nil,nil,nil 
    begin
      @session.execute(@get_stmt, name, shard.to_s).each do |row|
        due,id,message = row['due'],row['id'],row['message']
      end
    rescue StandardError => e
      @logger.error("StandardError occurred, unable to take: #{e}")
      return nil
    end
    return nil unless(message)
    @logger.debug("Got message from shard #{shard} due=#{due}, id=#{id}: #{message}")

    begin
      @logger.debug("Deleting from shard #{shard} message: due=#{due}, id=#{id}")
      @session.execute(@delete_stmt, name, shard.to_s,due,id)
    rescue StandardError => e
      @logger.error("StandardError occurred, unable to delete: #{e}")
      return nil
    end
    return message
  end


  private
    # The two 'clocks' allow for simulations of
    # clock skew
    def minute_timestamp_from_producer_clock
      t=Time.now
      t.strftime("%Y%j%H%M").to_i
    end

    def minute_timestamp_from_consumer_clock
      t=Time.now
      t.strftime("%Y%j%H%M").to_i
    end

    def calc_producer_shard(mts)
      mts % @number_of_shards
    end

    def calc_consumer_shard(mts)
      # Substract 2 to make sure there is one extra shard in between to
      # cope with producer/consumer clock skew of up to 60 seconds
      s = mts % @number_of_shards - 2
      s += @number_of_shards if(s < 0)
      s 
    end

end

