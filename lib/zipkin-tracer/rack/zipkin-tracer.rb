require 'rack'
require 'zipkin-tracer/config'
require 'zipkin-tracer/tracer_factory'
require 'zipkin-tracer/rack/zipkin_env'

module ZipkinTracer
  # This middleware reads Zipkin headers from the request and sets/creates a Trace.id usable by the rest of the app
  # It will also send the trace to the Zipkin service using one of the methods configured.
  class RackHandler
    def initialize(app, config = nil)
      @app = app
      @config = Config.new(app, config).freeze
      @tracer = TracerFactory.new.tracer(@config)
    end

    def call(env)
      zipkin_env = ZipkinEnv.new(env, @config)
      trace_id = zipkin_env.trace_id
      TraceContainer.with_trace_id(trace_id) do
        if !trace_id.sampled?
          @app.call(env)
        else
          @tracer.with_new_span(trace_id, span_name(env)) do |span|
            trace!(span, zipkin_env) { @app.call(env) }
          end
        end
      end
    end

    private

    def span_name(env)
      "#{env[Rack::REQUEST_METHOD].to_s.downcase} #{Application.route(env)}".strip
    end

    def annotate_plugin(span, env, status, response_headers, response_body)
      @config.annotate_plugin.call(span, env, status, response_headers, response_body) if @config.annotate_plugin
    end

    def trace!(span, zipkin_env, &block)
      status, headers, body = yield
    ensure
      trace_server_information(span, zipkin_env, status)
      annotate_plugin(span, zipkin_env.env, status, headers, body)
    end

    def trace_server_information(span, zipkin_env, status)
      span.kind = Trace::Span::Kind::SERVER
      span.record_status(status)
      span.record_tag(Trace::Span::Tag::URL, zipkin_env.url)
      span.record_tag(Trace::Span::Tag::METHOD, zipkin_env.env[Rack::REQUEST_METHOD])
    end
  end
end
