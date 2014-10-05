cassandra-ruby-queue
====================

Simple priority queue with Cassandra and Ruby

As an eventually consistent database, Cassandra cannot immediately erase
data when receiving a deletion query. Nodes might be down or temporarily
unreachable and such nodes would never be able to learn about a delete
when they come up again if information would just be erased.

To solve this situation Cassandra turns deleted data into tombstones that
serve as markers for the deletion, allowing consistency to eventually
take place. These markers will be kept around for the time period
controlled by the `gc_grace_seconds` per-table configuration option - 
per default set to 10 days (effectively allowing nodes to be 
unreachable for up to 10 days).

High delete frequencies cause these tombstones to pile up, eventually
slowing down reads because Cassandra will read the tombstones as part
of every read. When the ratio of tombstones to 'real' data goes up the
read performance is degraded (untile gc_grace_seconds is reached again,
causing compaction to clean up the tombstones).

This is the reason why queing use cases in general are said to be one of
the worst anti patterns for Cassandra.

Now, what if you are in a situation where you need some form of queuing
but which does not require the kind of throughput that demands a
specialized queuing system without doubt.

Can we not get Cassandra to queue the little things for us? The goal of
this project is to explore the possibilities and limitations.

# Distributing the Workload

Given that queing implies some form of ordering, it is clear that the
focus of a solution has to be the per-row sorting capabilities of
Cassandra. In order to avoid a hot spot in the cluster we cannot
put all messages in a single row and have producers and consumers
operate on that row. A solution for this problem is to distribute
the workload across a bunch of rows that act as shards of the
overall queue.

# Time Based Shard Selection

The easiest way to assign producers and consumers to active shards
at runtime is a time based soluton. To keep things simple, we'll
use a timestamp of minute-granularity and create the modulo of
the number of shards to select the active shard:

    shard = YYYYdddHHMM % number-of-shards

# Isolate Producer and Consumer

Let's take the idea a step further and leverage the sharding to
isolate producer and consumer.

    producer-shard = YYYYdddHHMM % number-of-shards
    consumer-shard = YYYYdddHHMM % number-of-shards - 2  (add number-of-shards if < 0)

What is the reason for the offset of two shards? Wouldn't one do the trick?
Well, in theory it would, but moving the consumer back an additional shard
solves the problem of clock skew between producer and consumer clocks. The
design can tolerate up to 60 seconds clock of skew before both parties meet
in the same shard.

Note that this implies that we use at least four shards, allowing an offset
of at least twi in both directions.

# Isolation Solves the Coordination Problem

A nice benefit of the isolation of producer and consumer is that it solves
the coordination between the two. Producers can just write into their
shard (Cassandra will take care of the sorting) while the consumer processes
another shard (we'll address the coordination of multiple consumers
at a later point in time).

# Shards as Time Ordered Priority Queues

Cassandra's per-row sorting capabilities make it simple to keep the queued
messages sorted by due-date while producers put messages in the queue, with
arbitrary due dates. To allow for message deletion we add a timeuuid as
a message ID upon insertion.

Here is the table:

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


The additional `name` component in the composite key is a user provided
additional shard, effectively identifying individual queues.

The `lock` static column is not used at the moment; this will be used
in combination with Cassandra 2.x conditional updates to achiece
consumer coordination.

Putting a message in the queue is done with

    insert into queue (name,shard,due,id,message) values (?,?,?,now(),?)

While consuming a message is necessarily a two step operation (hence
mandating consumer coordination):

    select due,id,message from queue where name = ? and shard = ? and due < dateOf(now()) limit 1
    
    delete from queue where name = ? and shard = ? and due = ? and id = ?

# The Tools

There are three Ruby scripts, a producer, a consumer and an observer that prints
out the current message count and pending message count for each shard.

The scripts use the new Datastax
[Cassandra driver for Ruby](https://github.com/datastax/ruby-driver)
Currently installation works best by downloading the source from github and
installing the gem from these sources directly.

Create a keyspace with at least replication factor 3 because the scripts use
quorum read and write consistency.

Start the observer:

    ./observer.rb -H <c* host ip> -K keyspace

Produce some messages:

    ./producer.rb -H <c* host ip> -K keyspace

Start a consumer:

    ./consumer.rb -H <c* host ip> -K keyspace

Have a look at the source code and play with different frequencies
etc.


# And the Tombstones?

Yes, that is right, we still have to address the original problem of the
 tombstones piling up. Well, for one, we have distributed the problem
horizontally across shards, smoothing out the negative impact. In
addition, the distribution across shards and the time based shard selection
yields periods of total inactivity for the shards - we will use these
periods to allow for compaction to cleanup the tombstones by setting
gc_grace_seconds to a very small number (Note: I started with 60 seconds
in the examples, but an evaluation of the most effective setting is pending).


 
# Acknowledgements

The general mechnism has been inspired by the
[message queue library](https://github.com/Netflix/astyanax/wiki/Message-Queue)
provided by Netflix as part of their [Astyanax](https://github.com/Netflix/astyanax) driver.

