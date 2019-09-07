HEX_REGEX = /\A\h{16}\z/

shared_examples 'makes requests without tracing' do
  context 'Tracer is not set' do
    before do
      Trace.tracer = nil
      ::Trace.sample_rate = 1 # make sure initialized
    end
    include_examples 'make requests', false
  end

  context 'We are not sampling this request' do
    before do
      Trace.tracer = Trace::NullSender.new
      ::Trace.sample_rate = 0 # make sure initialized
    end
    include_examples 'make requests', false
  end
end

shared_examples 'makes requests with tracing' do
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

  include_examples 'make requests', true
end

shared_examples 'make requests' do |expect_to_trace_request|
  let(:hostname) { 'service.example.com' }
  let(:host_ip) { 0x11223344 }
  let(:url_path) { '/some/path/here' }
  let(:raw_url) { "https://#{hostname}#{url_path}" }
  let(:tracer) { Trace.tracer }
  let(:trace_id) { ::Trace::TraceId.new(1, 2, 3, true, ::Trace::Flags::DEBUG) }

  # helper to check host component of annotation
  def expect_host(host, host_ip, service_name)
    expect(host).to be_a_kind_of(::Trace::Endpoint)
    expect(host.ipv4).to eq(host_ip)
    expect(host.service_name).to eq(service_name)
  end

  def expect_tracing
    expect(tracer).to receive(:start_span).with(anything, 'post').and_call_original
    expect(tracer).to receive(:end_span).with(anything).and_call_original

    expect_any_instance_of(Trace::Span).to receive(:kind=).with('CLIENT')

    expect_any_instance_of(Trace::Span).to receive(:remote_endpoint=) do |_, host|
      expect_host(host, hostname, service_name)
    end

    expect_any_instance_of(Trace::Span).to receive(:record_tag) do |_, key, value|
      expect(key).to eq('http.method')
      expect(value).to eq('POST')
    end

    expect_any_instance_of(Trace::Span).to receive(:record_tag) do |_, key, value|
      expect(key).to eq('http.path')
      expect(value).to eq(url_path)
    end

    expect_any_instance_of(Trace::Span).to receive(:record_tag) do |_, key, value|
      expect(key).to eq('http.status_code')
      expect(value).to eq('404')
    end

    expect_any_instance_of(Trace::Span).to receive(:record_tag) do |_, key, value|
      expect(key).to eq('error')
      expect(value).to eq('404')
    end
  end

  context 'with tracing id' do
    let(:trace_id) { ::Trace::TraceId.new(1, 2, 3, true, ::Trace::Flags::DEBUG) }

    it 'expects tracing' do
      if expect_to_trace_request
        expect_tracing
        process('', url)
      end
    end

    it 'expects tracing once even when called twice' do
      if expect_to_trace_request
        expect_tracing
        request_headers = process('', url)
        process('', url, request_headers)
      end
    end

    it 'sets the X-B3 request headers with a new spanID' do
      request_headers  = nil
      ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
        request_headers = process('', url)
      end

      expect(request_headers['X-B3-TraceId']).to eq('0000000000000001')
      expect(request_headers['X-B3-ParentSpanId']).to eq('0000000000000003')
      expect(request_headers['X-B3-SpanId']).not_to eq('0000000000000003')
      expect(request_headers['X-B3-SpanId']).to match(HEX_REGEX)
      expect(request_headers['X-B3-Sampled']).to eq('true')
      expect(request_headers['X-B3-Flags']).to eq('1')
    end

    it 'the original spanID is restored after the calling the middleware' do
      old_trace_id = ZipkinTracer::TraceContainer.current
      ZipkinTracer::TraceContainer.with_trace_id(old_trace_id) do
        process('', url)
      end
      expect(ZipkinTracer::TraceContainer.current).to eq(old_trace_id)
    end
  end

  context 'without tracing id' do
    it 'expects tracing' do
      if expect_to_trace_request
        expect_tracing
        process('', url)
      end
    end

    it 'generates a new ID, and sets the X-B3 request headers' do
      request_headers = process('', url)

      expect(request_headers['X-B3-TraceId']).to match(HEX_REGEX)
      expect(request_headers['X-B3-ParentSpanId']).to match(HEX_REGEX)
      expect(request_headers['X-B3-SpanId']).to match(HEX_REGEX)
      expect(request_headers['X-B3-Sampled']).to match(/(true|false)/)
      expect(request_headers['X-B3-Flags']).to match(/(1|0)/)
    end
  end

  context 'Trace has not been sampled' do
    let(:trace_id) { ::Trace::TraceId.new(1, 2, 3, false, 0) }

    it 'sets the X-B3 request headers with a new spanID' do
      request_headers = nil
      ZipkinTracer::TraceContainer.with_trace_id(trace_id) do
        request_headers = process('', url)
      end

      expect(request_headers['X-B3-TraceId']).to eq('0000000000000001')
      expect(request_headers['X-B3-ParentSpanId']).to eq('0000000000000003')
      expect(request_headers['X-B3-SpanId']).not_to eq('0000000000000003')
      expect(request_headers['X-B3-SpanId']).to match(HEX_REGEX)
      expect(request_headers['X-B3-Sampled']).to eq('false')
      expect(request_headers['X-B3-Flags']).to eq('0')
    end

    it 'the original spanID is restored after the calling the middleware' do
      old_trace_id = ZipkinTracer::TraceContainer.current
      ZipkinTracer::TraceContainer.with_trace_id(old_trace_id) do
        process('', url)
      end
      expect(ZipkinTracer::TraceContainer.current).to eq(old_trace_id)
    end

    it 'does not trace the request' do
      expect(tracer).not_to receive(:set_rpc_name)
      expect(tracer).not_to receive(:record)
      process('', url)
    end

    it 'does not create any annotation' do
      expect(Trace::Annotation).not_to receive(:new)
      process('', url)
    end
  end

  context 'when looking up hostname raises' do
    let(:host_ip) { 0x7f000001 } # expect stubbed 'null' IP

    before do
      allow(::Trace::Endpoint).to receive(:host_to_i32).with(hostname).and_raise(SocketError)
    end

    it 'expects tracing' do
      if expect_to_trace_request
        expect_tracing
        process('', url)
      end
    end
  end
end
