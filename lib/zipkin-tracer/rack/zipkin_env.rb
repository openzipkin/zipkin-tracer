module ZipkinTracer
  # This class manages the Zipkin related information in the Rack environment.
  # It is only used by the rack middleware.
  class ZipkinEnv
    attr_reader :env

    def initialize(env, config)
      @env    = env
      @config = config
    end

    def trace_id(default_flags = Trace::Flags::EMPTY)
      trace_id, span_id, parent_span_id, shared = retrieve_or_generate_ids
      sampled = sampled_header_value(@env['HTTP_X_B3_SAMPLED'])
      flags = (@env['HTTP_X_B3_FLAGS'] || default_flags).to_i
      Trace::TraceId.new(trace_id, parent_span_id, span_id, sampled, flags, shared)
    end

    def called_with_zipkin_headers?
      @called_with_zipkin_headers ||= B3_REQUIRED_HEADERS.all? { |key| @env.key?(key) }
    end

    def url
      Rack::Request.new(env).url
    end

    private

    B3_REQUIRED_HEADERS = %w(HTTP_X_B3_TRACEID HTTP_X_B3_SPANID).freeze
    B3_OPT_HEADERS = %w(HTTP_X_B3_PARENTSPANID HTTP_X_B3_SAMPLED HTTP_X_B3_FLAGS).freeze

    def retrieve_or_generate_ids
      if called_with_zipkin_headers?
        trace_id, span_id = @env.values_at(*B3_REQUIRED_HEADERS)
        parent_span_id = @env['HTTP_X_B3_PARENTSPANID']
        shared = true
      else
        span_id = TraceGenerator.new.generate_id
        trace_id = TraceGenerator.new.generate_id_from_span_id(span_id)
        parent_span_id = nil
        shared = false
      end
      [trace_id, span_id, parent_span_id, shared]
    end

    def new_sampled_header_value(sampled)
      case [@config.sampled_as_boolean, sampled]
      when [true, true]
        'true'
      when [true, false]
        'false'
      when [false, true]
        '1'
      when [false, false]
        '0'
      end
    end

    def current_trace_sampled?
      rand < @config.sample_rate
    end

    def sampled_header_value(parent_trace_sampled)
      if parent_trace_sampled # A service upstream decided this goes in all the way
        parent_trace_sampled
      else
        new_sampled_header_value(force_sample? || current_trace_sampled? && !filtered? && routable_request?)
      end
    end

    def force_sample?
      @config.whitelist_plugin && @config.whitelist_plugin.call(@env)
    end

    def filtered?
      @config.filter_plugin && !@config.filter_plugin.call(@env)
    end

    def routable_request?
      Application.routable_request?(@env)
    end

  end
end
