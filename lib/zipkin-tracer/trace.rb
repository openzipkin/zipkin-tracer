require 'zipkin-tracer/zipkin_sender_base'
require 'zipkin-tracer/trace_container'
# Most of this code is copied from Finagle
# https://github.com/twitter/finagle/blob/finagle-6.39.0/finagle-thrift/src/main/ruby/lib/finagle-thrift/trace.rb
# But moved and improved here.
module Trace
  # These methods and attr_accessor below are used as global configuration of this gem
  # Most of these are set by the config class and then used around.
  # TODO: Move this out of the Trace module , take out that extend self and be happier
  extend self
  attr_accessor :trace_id_128bit

  # This method is deprecated, please use TraceGenerator.current
  # Note that this method will always return a trace, it will
  # generate a new one if none was available.
  def id
    ZipkinTracer::TraceGenerator.new.current
  end

  def self.tracer
    @tracer
  end

  def self.sample_rate
    @sample_rate
  end

  def self.tracer=(tracer)
    @tracer = tracer
  end

  def self.sample_rate=(sample_rate)
    if sample_rate > 1 || sample_rate < 0
      raise ArgumentError.new("sample rate must be [0,1]")
    end
    @sample_rate = sample_rate
  end

  def default_endpoint=(endpoint)
    @default_endpoint = endpoint
  end

  def default_endpoint
    @default_endpoint
  end

  # These classes all come from Finagle-thrift + some needed modifications (.to_h)
  # Moved here as a first step, eventually move them out of the Trace module

  class Annotation
    attr_reader :value, :timestamp

    def initialize(value)
      @timestamp = (Time.now.to_f * 1000 * 1000).to_i # micros
      @value = value
    end

    def to_h
      {
        value: @value,
        timestamp: @timestamp
      }
    end
  end

  class Flags
    # no flags set
    EMPTY = 0
    # the debug flag is used to ensure we pass all the sampling layers and that the trace is stored
    DEBUG = 1
  end

  class SpanId
    HEX_REGEX = /^[a-f0-9]{16,32}$/i
    MAX_SIGNED_I64 = 9223372036854775807
    MASK = (2 ** 64) - 1

    def self.from_value(v)
      if v.is_a?(String) && v =~ HEX_REGEX
        # drops any bits higher than 64 by selecting right-most 16 characters
        new(v.length > 16 ? v[v.length - 16, 16].hex : v.hex)
      elsif v.is_a?(Numeric)
        new(v)
      elsif v.is_a?(SpanId)
        v
      end
    end

    def initialize(value)
      @value = value
      @i64 = if @value > MAX_SIGNED_I64
        -1 * ((@value ^ MASK) + 1)
      else
        @value
      end
    end

    def to_s; "%016x" % @value; end
    def to_i; @i64; end
  end

  # A TraceId contains all the information of a given trace id
  class TraceId
    attr_reader :trace_id, :parent_id, :span_id, :sampled, :flags, :shared

    def initialize(trace_id, parent_id, span_id, sampled, flags, shared = false)
      @trace_id = Trace.trace_id_128bit ? TraceId128Bit.from_value(trace_id) : SpanId.from_value(trace_id)
      @parent_id = parent_id.nil? ? nil : SpanId.from_value(parent_id)
      @span_id = SpanId.from_value(span_id)
      @sampled = sampled
      @flags = flags
      @shared = shared
    end

    def next_id
      TraceId.new(@trace_id, @span_id, ZipkinTracer::TraceGenerator.new.generate_id, @sampled, @flags)
    end

    # the debug flag is used to ensure the trace passes ALL samplers
    def debug?
      @flags & Flags::DEBUG == Flags::DEBUG
    end

    def sampled?
      debug? || ['1', 'true'].include?(@sampled)
    end

    def to_s
      "TraceId(trace_id = #{@trace_id.to_s}, parent_id = #{@parent_id.to_s}, span_id = #{@span_id.to_s}," \
      " sampled = #{@sampled.to_s}, flags = #{@flags.to_s}, shared = #{@shared.to_s})"
    end
  end

  class TraceId128Bit < SpanId
    HEX_REGEX_16 = /^[a-f0-9]{16}$/i
    HEX_REGEX_32 = /^[a-f0-9]{32}$/i
    MAX_SIGNED_I128 = (2 ** 128 / 2) -1
    MASK = (2 ** 128) - 1

    def self.from_value(v)
      if v.is_a?(String) && v =~ HEX_REGEX_16
        SpanId.new(v.hex)
      elsif v.is_a?(String) && v =~ HEX_REGEX_32
        new(v.hex)
      elsif v.is_a?(Numeric)
        new(v)
      elsif v.is_a?(SpanId)
        v
      end
    end

    def initialize(value)
      @value = value
      @i128 = if @value > MAX_SIGNED_I128
        -1 * ((@value ^ MASK) + 1)
      else
        @value
      end
    end

    def to_s; '%032x' % @value; end
    def to_i; @i128; end
  end

  # A span may contain many annotations
  class Span
    module Tag
      METHOD = "http.method".freeze
      PATH = "http.path".freeze
      URL = "http.url".freeze
      STATUS = "http.status_code".freeze
      LOCAL_COMPONENT = "lc".freeze # TODO: Remove LOCAL_COMPONENT and related methods when no longer needed
      ERROR = "error".freeze
    end

    module Kind
      CLIENT = "CLIENT".freeze
      SERVER = "SERVER".freeze
    end

    attr_accessor :name, :kind, :local_endpoint, :remote_endpoint, :annotations, :tags, :debug

    def initialize(name, span_id)
      @name = name
      @span_id = span_id
      @kind = nil
      @local_endpoint = nil
      @remote_endpoint = nil
      @annotations = []
      @tags = {}
      @debug = span_id.debug?
      @timestamp = to_microseconds(Time.now)
      @duration = UNKNOWN_DURATION
    end

    def close
      @duration = to_microseconds(Time.now) - @timestamp
    end

    def to_h
      h = {
        name: @name,
        traceId: @span_id.trace_id.to_s,
        id: @span_id.span_id.to_s,
        localEndpoint: @local_endpoint.to_h,
        timestamp: @timestamp,
        duration: @duration,
        debug: @debug
      }
      h[:parentId] = @span_id.parent_id.to_s unless @span_id.parent_id.nil?
      h[:kind] = @kind unless @kind.nil?
      h[:remoteEndpoint] = @remote_endpoint.to_h unless @remote_endpoint.nil?
      h[:annotations] = @annotations.map(&:to_h) unless @annotations.empty?
      h[:tags] = @tags unless @tags.empty?
      h[:shared] = true if @span_id.shared
      h
    end

    # We record information into spans, then we send these spans to zipkin
    def record(value)
      annotations << Trace::Annotation.new(value.to_s)
    end

    def record_tag(key, value)
      @tags[key] = value.to_s
    end

    def record_local_component(value)
      record_tag(Tag::LOCAL_COMPONENT, value)
    end

    def has_parent_span?
      !@span_id.parent_id.nil?
    end

    STATUS_ERROR_REGEXP = /\A(4.*|5.*)\z/.freeze

    def record_status(status)
      return if status.nil?
      status = status.to_s
      record_tag(Tag::STATUS, status)
      record_tag(Tag::ERROR, status) if STATUS_ERROR_REGEXP.match(status)
    end

    private

    UNKNOWN_DURATION = 0 # mark duration was not set

    def to_microseconds(time)
      (time.to_f * 1_000_000).to_i
    end
  end

  class Endpoint < Struct.new(:ipv4, :port, :service_name)
    UNKNOWN_URL = 'unknown'.freeze

    def self.local_endpoint(service_name)
      hostname = Socket.gethostname
      Endpoint.new(hostname, nil, service_name)
    end

    def self.remote_endpoint(url, remote_service_name)
      service_name = remote_service_name || url.host.split('.').first || UNKNOWN_URL # default to url-derived service name
      Endpoint.new(url.host, url.port, service_name)
    end

    def to_h
      hsh = {
        ipv4: ipv4,
        serviceName: service_name
      }
      hsh[:port] = port if port
      hsh
    end
  end
end
