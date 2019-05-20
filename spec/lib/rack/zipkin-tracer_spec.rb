require 'rack/mock'
require 'spec_helper'

describe ZipkinTracer::RackHandler do
  def middleware(app, config={})
    configuration = { sample_rate: 1 }.merge(config)
    described_class.new(app, configuration)
  end

  def mock_env(path = '/', params = {})
    Rack::MockRequest.env_for(path, params)
  end

  def mock_env_route(path = '/thing/123', params = {})
    Rack::MockRequest.env_for(path, params)
  end

  def expect_host(host)
    expect(host).to be_a_kind_of(Trace::Endpoint)
    expect(host.ipv4).to eq(host_ip)
  end

  def expect_tags(path = '/')
    url = "http://example.org#{path}"
    expect_any_instance_of(Trace::Span).to receive(:kind=).with(Trace::Span::Kind::SERVER)
    expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.url', url)
    expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.status_code', '200')
    expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.method', 'GET')
  end

  let(:app_status) { 200 }
  let(:app_headers) { { 'Content-Type' => 'text/plain' } }
  let(:app_body) { path }
  let(:path) { '/'}
  let(:tracer) { Trace.tracer }

  let(:app) {
    lambda { |env|
      [app_status, app_headers, [env['PATH_INFO']]]
    }
  }

  # stub ip address lookup
  let(:host_ip) { 0x11223344 }
  before do
    allow(::Trace::Endpoint).to receive(:host_to_i32).and_return(host_ip)
    allow(ZipkinTracer::Application).to receive(:logger).and_return(Logger.new(nil))
  end

  let(:tracer) {subject.instance_variable_get(:@tracer)}

  shared_examples_for 'traces the request' do
    it 'traces the request' do
      expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
      expect(tracer).to receive(:with_new_span).ordered.with(anything, 'get').and_call_original
      expect_tags

      status, headers, body = subject.call(mock_env)
      expect(status).to eq(app_status)
      expect(headers).to eq(app_headers)
      expect { |b| body.each &b }.to yield_with_args(app_body)
    end
  end

  context 'Using Rails' do
    subject { middleware(app) }

    context 'accessing a valid URL "/" of our service' do
      before do
        allow(ZipkinTracer::Application).to receive(:routable_request?).and_return(true)
        allow(ZipkinTracer::Application).to receive(:get_route).and_return(nil)
      end

      it_should_behave_like 'traces the request'
    end

    context 'accessing a valid URL "/thing/123" of our service' do
      before do
        allow(ZipkinTracer::Application).to receive(:routable_request?).and_return(true)
        allow(ZipkinTracer::Application).to receive(:route).and_return("/thing/:id")
      end

      it 'traces the request' do
        expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
        expect(tracer).to receive(:with_new_span).ordered.with(anything, 'get /thing/:id').and_call_original
        expect_tags('/thing/123')

        status, headers, body = subject.call(mock_env_route)
        expect(status).to eq(app_status)
        expect(headers).to eq(app_headers)
        expect { |b| body.each &b }.to yield_with_args("/thing/123")
      end
    end

    context 'accessing an invalid URL of our service' do
      before do
        allow(ZipkinTracer::Application).to receive(:routable_request?).and_return(false)
      end

      it 'calls the app and does not trace the request' do
        expect_any_instance_of(Trace::Span).not_to receive(:record)

        status, _, body = subject.call(mock_env)
        # return expected status
        expect(status).to eq(200)
        expect { |b| body.each &b }.to yield_with_args(app_body)
      end
    end
  end

  context 'configured without plugins' do
    subject { middleware(app) }

    it_should_behave_like 'traces the request'

    context 'record raises socket related errors' do
      it 'calls the app normally' do
        allow(::Trace).to receive(:record).and_raise(Errno::EBADF)
        status, _, body = subject.call(mock_env)
        # return expected status
        expect(status).to eq(200)
        expect { |b| body.each &b }.to yield_with_args(app_body)
      end
    end

    context 'Zipkin methods raise exceptions' do
      it 'calls the app normally' do
        allow(::Trace).to receive(:set_rpc_name).and_raise(StandardError)
        status, _, body = subject.call(mock_env)
        # return expected status
        expect(status).to eq(200)
        expect { |b| body.each &b }.to yield_with_args(app_body)
      end
    end


    context 'with sample rate set to 0' do
      subject { middleware(app, { sample_rate: 0 }) }

      it 'Trace is created but it is not sent to zipkin' do
        expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
        expect(::Trace).not_to receive(:record)
        status, _, _ = subject.call(mock_env)
        expect(status).to eq(200)
      end

      it 'always samples if debug flag is passed in header' do
        expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
        status, _, _ = subject.call(
          mock_env('/', 'HTTP_X_B3_FLAGS' => ::Trace::Flags::DEBUG.to_s))

        # return expected status
        expect(status).to eq(200)
      end
    end
  end

  context 'configured with annotation plugin' do
    let(:annotate) do
      lambda do |span, env, status, response_headers, response_body|
        # string annotation
        span.record_tag('foo', env['foo'] || 'FOO')
        # integer annotation
        span.record_tag('http.status_code', status)
      end
    end
    subject { middleware(app, annotate_plugin: annotate) }

    it 'traces a request with additional annotations' do
      expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
      expect(tracer).to receive(:with_new_span).and_call_original.ordered
      expect_tags
      expect_any_instance_of(Trace::Span).to receive(:record_tag).with('http.status_code', 200)
      expect_any_instance_of(Trace::Span).to receive(:record_tag).with('foo', 'FOO')

      status, _, _ = subject.call(mock_env)

      # return expected status
      expect(status).to eq(200)
    end
  end

  context 'configured with filter plugin that allows all' do
    subject { middleware(app, filter_plugin: lambda { |env| true }) }

    it_should_behave_like 'traces the request'
  end

  context 'configured with filter plugin that allows none' do
    subject { middleware(app, filter_plugin: lambda { |env| false }) }

    it 'does not send the trace to zipkin' do
      expect(ZipkinTracer::TraceContainer).to receive(:with_trace_id).and_call_original
      expect(::Trace).not_to receive(:record)
      status, _, _ = subject.call(mock_env)
      expect(status).to eq(200)
    end
  end

  context 'with sample rate set to 0' do

    context 'configured with whitelist plugin that forces sampling' do
      subject { middleware(app, whitelist_plugin: lambda { |env| true }, sample_rate: 0) }

      it 'samples the request' do
        expect_tags
        status, _, _ = subject.call(mock_env)
        expect(status).to eq(200)
      end
    end

    context 'configured with filter plugin that allows none' do
      subject { middleware(app, whitelist_plugin: lambda { |env| false }) }

      it_should_behave_like 'traces the request'

    end
  end
end
