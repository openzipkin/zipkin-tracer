require 'faraday'
require 'uri'

module ZipkinTracer
  # Faraday middleware. It will add CR/CS annotations to outgoing connections done by Faraday
  class FaradayHandler < ::Faraday::Middleware
    def initialize(app, service_name = nil)
      @app = app
      @service_name = service_name
    end

    def call(env)
      trace_id = TraceGenerator.new.next_trace_id
      TraceContainer.with_trace_id(trace_id) do
        b3_headers.each do |method, header|
          env[:request_headers][header] = trace_id.send(method).to_s
        end
        if Trace.tracer && trace_id.sampled?
          trace!(env, trace_id)
        else
          @app.call(env)
        end
      end
    end

    private

    def b3_headers
      {
        trace_id: 'X-B3-TraceId',
        parent_id: 'X-B3-ParentSpanId',
        span_id: 'X-B3-SpanId',
        sampled: 'X-B3-Sampled',
        flags: 'X-B3-Flags'
      }
    end

    def trace!(env, trace_id)
      response = nil
      # handle either a URI object (passed by Faraday v0.8.x in testing), or something string-izable
      method = env[:method].to_s
      url = env[:url].respond_to?(:host) ? env[:url] : URI.parse(env[:url].to_s)
      remote_endpoint = Trace::Endpoint.remote_endpoint(url, @service_name) # The endpoint we are calling.
      Trace.tracer.with_new_span(trace_id, method.downcase) do |span|
        @span = span # So we can record on exceptions
        # annotate with method (GET/POST/etc.) and uri path
        span.kind = Trace::Span::Kind::CLIENT
        span.remote_endpoint = remote_endpoint
        span.record_tag(Trace::Span::Tag::METHOD, method.upcase)
        span.record_tag(Trace::Span::Tag::URL, url.to_s)
        response = @app.call(env).on_complete do |renv|
          span.record_status(renv[:status])
        end
      end
      response
    rescue Net::ReadTimeout
      record_error(@span, 'Request timed out.')
      raise
    rescue Faraday::ConnectionFailed
      record_error(@span, 'Request connection failed.')
      raise
    rescue Faraday::ClientError
      record_error(@span, 'Generic Faraday client error.')
      raise
    end

    def record_error(span, msg)
      span.record_tag(Trace::Span::Tag::ERROR, msg)
    end

  end
end
