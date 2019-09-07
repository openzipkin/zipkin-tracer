require 'spec_helper'
require 'zipkin-tracer/zipkin_null_sender'
require 'lib/middleware_shared_examples'

describe ZipkinTracer::ExconHandler do
  # returns the request headers
  def process(body, url, headers = {})
    stub_request(:post, url).to_return(status: 404, body: body, headers: headers)

    connection = Excon.new(url.to_s,
                           body: body,
                           method: :post,
                           headers: headers,
                           middlewares: [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
                          )
    connection.request

    return headers if !headers.empty?
    request_headers = nil
    expect(a_request(:post, url).with { |req|
      # Webmock 'normalizes' the headers. E.g: X-B3-TraceId becomes X-B3-Traceid.
      # See here:
      # https://github.com/bblimke/webmock/blob/a4aad22adc622699a8ea14c70d04acef8f67a512/lib/webmock/util/headers.rb#L9
      # So here, headers are manually fetched.
      request_headers = {
        'X-B3-TraceId' => req.headers['X-B3-Traceid'],
        'X-B3-ParentSpanId' => req.headers['X-B3-Parentspanid'],
        'X-B3-SpanId' => req.headers['X-B3-Spanid'],
        'X-B3-Sampled' => req.headers['X-B3-Sampled'],
        'X-B3-Flags' => req.headers['X-B3-Flags']
      }
    }).to have_been_made

    request_headers
  end

  context 'middleware configured (without service_name)' do
    let(:service_name) { URI(url).host }

    context 'request with string URL' do
      let(:url) { raw_url }

      include_examples 'makes requests with tracing'
      include_examples 'makes requests without tracing'
    end

    context 'request with pre-parsed URL' do
      let(:url) { URI.parse(raw_url) }

      include_examples 'makes requests with tracing'
      include_examples 'makes requests without tracing'
    end
  end

  it 'has a trace with correct duration' do
    request_duration_in_seconds = 1
    Timecop.freeze
    Trace.tracer = Trace::NullSender.new
    ::Trace.sample_rate = 1
    trace_id = ::Trace::TraceId.new(1, 2, 3, true, ::Trace::Flags::DEBUG)
    url = 'https://www.example.com'
    allow(::Trace).to receive(:default_endpoint)
      .and_return(::Trace::Endpoint.new('127.0.0.1', '80', 'example.com'))
    sleep_a_second = lambda do |request|
      Timecop.travel(Time.now + request_duration_in_seconds)
      ""
    end
    stub_request(:post, url)
      .to_return(body: sleep_a_second)
    connection = Excon.new(url.to_s,
                          body: '',
                          method: :post,
                          headers: {},
                          middlewares: [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
                          )

    span = Trace::Span.new('span', trace_id)
    allow(Trace::Span).to receive(:new).and_return(span)
    allow(span).to receive(:close).and_call_original

    ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
      connection.request
    end

    expect(span).to have_received(:close)
    expect(span.to_h[:duration]).to be > request_duration_in_seconds * 1_000_000
    Timecop.return
  end

  context 'configured with service_name "foo"' do
    let(:service_name) { url.host }

    context 'request with pre-parsed URL' do
      let(:url) { URI.parse(raw_url) }

      include_examples 'makes requests with tracing'
      include_examples 'makes requests without tracing'
    end

    context 'request with path and query params' do
      around do |example|
        Trace.tracer = Trace::NullSender.new
        ::Trace.sample_rate = 1 # make sure initialized
        ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
          example.run
        end
      end

      before do
        allow(::Trace).to receive(:default_endpoint).and_return(::Trace::Endpoint.new('127.0.0.1', '80', service_name))
        allow(::Trace::Endpoint).to receive(:host_to_i32).with(hostname).and_return(host_ip)
      end

      let(:hostname) { 'service.example.com' }
      let(:host_ip) { 0x11223344 }
      let(:raw_url) { "https://#{hostname}#{url_path}" }
      let(:tracer) { Trace.tracer }
      let(:trace_id) { ::Trace::TraceId.new(1, 2, 3, true, ::Trace::Flags::DEBUG) }
      let(:url) { URI.parse(raw_url) }

      context 'query params are in path' do
        let(:url_path) { '/some/path/here?query=params' }

        it 'queries the path without query' do
          stub_request(:post, url)
            .to_return(status: 200, body: '', headers: {})
          ENV['ZIPKIN_SERVICE_NAME'] = service_name

          connection = Excon.new(url.to_s,
                                body: '',
                                method: :post,
                                headers: {},
                                middlewares: [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
                                )

          span = spy('Trace::Span')
          allow(Trace::Span).to receive(:new).and_return(span)

          expect(span).to receive(:record_tag).with("http.path", "/some/path/here")

          ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
            connection.request
          end
        end
      end

      context 'query params are in hash' do
        let(:url_path) { '/some/path/here' }

        it 'queries without the query even when query is a hash' do
          stub_request(:post, url.to_s + "?query=params")
            .to_return(status: 200, body: '', headers: {})
          ENV['ZIPKIN_SERVICE_NAME'] = service_name

          connection = Excon.new(url.to_s,
                                body: '',
                                method: :post,
                                headers: {},
                                middlewares: [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
                                )

          span = spy('Trace::Span')
          allow(Trace::Span).to receive(:new).and_return(span)

          expect(span).to receive(:record_tag).with("http.path", "/some/path/here")

          ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
            connection.request(path: url_path, query: { query: "params" })
          end
        end
      end
    end

    context 'request with custom zipkin service name' do
      around do |example|
        Trace.tracer = Trace::NullSender.new
        ::Trace.sample_rate = 1 # make sure initialized
        ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
          example.run
        end
      end
      before do
        allow(::Trace).to receive(:default_endpoint).and_return(::Trace::Endpoint.new('127.0.0.1', '80', service_name))
        allow(::Trace::Endpoint).to receive(:host_to_i32).with(hostname).and_return(host_ip)
      end


      let(:hostname) { 'service.example.com' }
      let(:host_ip) { 0x11223344 }
      let(:raw_url) { "https://#{hostname}#{url_path}" }
      let(:tracer) { Trace.tracer }
      let(:trace_id) { ::Trace::TraceId.new(1, 2, 3, true, ::Trace::Flags::DEBUG) }
      let(:url) { URI.parse(raw_url) }

      let(:url_path) { '/some/path/here' }

      it 'uses the service name' do
        stub_request(:post, url)
          .to_return(status: 200, body: '', headers: {})

        connection = Excon.new(url.to_s,
                              body: '',
                              zipkin_service_name: "fake-service-name",
                              method: :post,
                              headers: {},
                              middlewares: [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
                              )

        span = spy('Trace::Span')
        allow(Trace::Span).to receive(:new).and_return(span)

        expect(span).to receive(:remote_endpoint=) do |host|
          expect(host.service_name).to eql("fake-service-name")
        end.once

        ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
          connection.request
        end
      end

      it 'traces the response status' do
        stub_request(:get, url)
          .to_return(status: 200, body: '', headers: {})

        expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.path', "/some/path/here")
        expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.status_code', '200')
        expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.method', 'GET')

        ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
          middlewares = [ZipkinTracer::ExconHandler] + Excon.defaults[:middlewares]
          Excon.get(url.to_s, middlewares: middlewares)
        end
      end
    end
  end
end
