# frozen_string_literal: true

# RollingCache is a simple, high-performance FIFO cache,
# but with some of the most evil design choices possible.
# It stores entries in a Redis stream and depends on Redis
# to trim the oldest entries on insertion.
class RollingCache
  include Redisable

  # Initialize an instance backed by +key+ and limited to
  # +size+ entries. No Redis command will be sent until
  # #push or #get is called.
  def initialize(key, size)
    @key = key
    @size = size

    if redis.respond_to?(:redis)
      # Bypass redis-namespace because it does not support streams yet
      @redis = redis.redis
    else
      @redis = redis
    end
  end

  # Cache an object. Returns an ID of the entry.
  #
  # The object is serialized with #dump and appended to the
  # Redis stream with `XADD` command. The stream will be
  # automatically trimmed to approximately the maximum
  # length passed to #initialize.
  #
  # For ActiveRecord objects, a list of symbols can be
  # given. Attributes specified in that list will be
  # plucked out and saved directly into the cache. Such
  # objects will be frozen when loaded.
  #
  # Example:
  #
  #   push(object)
  #   push(object, :id, :name)
  def push(...)
    @redis.xadd(@key, dump(...), approximate: true, maxlen: @size)
  end

  def push_multi(entries, *args)
    result = []

    @redis.pipelined do |pipeline|
      result = entries.map do |entry|
        pipeline.xadd(@key, dump(entry, *args), approximate: true, maxlen: @size)
      end
    end

    result.map!(&:value)
  end

  # Load the object saved under +id+. Returns nil if the
  # entry is not found or was deleted.
  def get(id)
    records = @redis.xrange(@key, id, id)

    return if records.empty?

    load(records[0][1])
  end

  # Dump an object into a Hash.
  #
  # For ActiveRecord objects, a list of symbols is
  # additionally received. In this case, the attributes
  # specified in that list will be plucked out from the
  # object.
  #
  # If no extra arguments are given, the object will be
  # serialized with Marshal::dump.
  #
  # If extra arguments are given, the required fields will
  # be plucked into a BSON document. For large objects,
  # this mode is significantly faster than marshalling the
  # whole object entirely.
  #
  # The reason not to use JSON: binary-safety.
  #
  # The reason not to use MsgPack: its extension type
  # registry is a little clumsy when handling ActiveRecord
  # objects. Also, people will ask why not use CBOR.
  #
  # Therefore, we abuse BSON for the moment. If we can
  # be this fast with BSON, we surely can achieve much
  # higher throughput with some well-thought-out caching
  # scheme.
  def dump(entry, *args)
    if args.empty?
      {
        'type' => 'marshal',
        'content' => Marshal.dump(entry)
      }
    else
      content = {}

      args.each do |sym|
        val = entry.public_send(sym)
        # If not directly serializable in BSON, call Marshal::dump first
        # If an object is serializable in BSON but contains another non-serializable
        # object, it is very likely we should implement `to_bson` in that object first
        # Otherwise, we just don't care because MsgPack also has trouble handling them
        val = BSON::Binary.new(Marshal.dump(val), :user) unless val.respond_to?(:to_bson)
        content[sym] = val
      end

      {
        'type' => 'bson',
        'class' => entry.class.name,
        'content' => content.to_bson.to_s
      }
    end
  end

  # Load an object from a Hash.
  def load(data)
    case data['type']
    when 'bson'
      attributes = {}

      Hash.from_bson(BSON::ByteBuffer.new(data['content'])).each do |key, val|
        if val.is_a?(BSON::Binary)
          field = val.data
          field = Marshal.load(field) if val.type == :user
        else
          field = val
        end

        attributes[key] = ActiveModel::Attribute.with_cast_value(key, field, nil)
      end

      data['class'].constantize.allocate.init_with_attributes(ActiveModel::AttributeSet.new(attributes).freeze)
    when 'marshal'
      Marshal.load(data['content'])
    end
  end
end
