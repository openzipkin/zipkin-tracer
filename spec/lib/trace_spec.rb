require 'spec_helper'

describe Trace do
  let(:dummy_endpoint) { Trace::Endpoint.new('127.0.0.1', 9411, 'DummyService') }
  let(:trace_id_128bit) { false }

  before do
    allow(Trace).to receive(:trace_id_128bit).and_return(trace_id_128bit)
  end

  it "id returns the next generator id" do
    expect_any_instance_of(ZipkinTracer::TraceGenerator).to receive(:current)
    Trace.id
  end

  describe Trace::TraceId do
    let(:traceid) { '234555b04cf7e099' }
    let(:span_id) { 'c3a555b04cf7e099' }
    let(:parent_id) { 'f0e71086411b1445' }
    let(:sampled) { true }
    let(:flags) { Trace::Flags::EMPTY }
    let(:trace_id) { Trace::TraceId.new(traceid, parent_id, span_id, sampled, flags) }

    it 'is not a debug trace' do
      expect(trace_id.debug?).to eq(false)
    end

    context 'sampled value is 0' do
      let(:sampled) { '0' }
      it 'is not sampled' do
        expect(trace_id.sampled?).to eq(false)
      end
    end
    context 'sampled value is false' do
      let(:sampled) { 'false' }
      it 'is sampled' do
        expect(trace_id.sampled?).to eq(false)
      end
    end
    context 'sampled value is 1' do
      let(:sampled) { '1' }
      it 'is sampled' do
        expect(trace_id.sampled?).to eq(true)
      end
    end
    context 'sampled value is true' do
      let(:sampled) { 'true' }
      it 'is sampled' do
        expect(trace_id.sampled?).to eq(true)
      end
    end

    context 'using the debug flag' do
      let(:flags) { Trace::Flags::DEBUG }
      it 'is a debug trace' do
        expect(trace_id.debug?).to eq(true)
      end
      it 'get sampled' do
        expect(trace_id.sampled?).to eq(true)
      end
    end

    context 'trace_id_128bit is false' do
      let(:traceid) { '5af30660491a5a27234555b04cf7e099' }

      it 'drops any bits higher than 64 bit' do
        expect(trace_id.trace_id.to_s).to eq('234555b04cf7e099')
      end
    end

    context 'trace_id_128bit is true' do
      let(:trace_id_128bit) { true }
      let(:traceid) { '5af30660491a5a27234555b04cf7e099' }

      it 'returns a 128-bit trace_id ' do
        expect(trace_id.trace_id.to_s).to eq(traceid)
      end
    end
  end

  describe Trace::TraceId128Bit do
    let(:traceid) { '234555b04cf7e099' }
    let(:traceid_128bit) { '5af30660491a5a27234555b04cf7e099' }
    let(:traceid_numeric) { 120892377080251878477690677995565998233 }
    let(:trace_id_128bit_instance) { described_class.from_value(traceid_128bit) }

    describe '.from_value' do
      it 'returns SpanId instance when traceid is 64-bit' do
        expect(described_class.from_value(traceid)).to be_instance_of(Trace::SpanId)
      end

      it 'returns TraceId128Bit instance when traceid is 128-bit' do
        expect(described_class.from_value(traceid_128bit)).to be_instance_of(described_class)
      end

      it 'returns TraceId128Bit instance when numeric value is given' do
        expect(described_class.from_value(traceid_numeric)).to be_instance_of(described_class)
      end

      it 'returns TraceId128Bit instance when TraceId128Bit instance is given' do
        expect(described_class.from_value(trace_id_128bit_instance)).to be_instance_of(described_class)
      end
    end

    describe '#to_s' do
      it 'returns trace_id value in string' do
        expect(trace_id_128bit_instance.to_s).to eq(traceid_128bit)
      end
    end

    describe '#to_i' do
      it 'returns trace_id value in integer' do
        expect(trace_id_128bit_instance.to_i).to eq(traceid_numeric)
      end
    end
  end

  describe Trace::Span do
    let(:span_id) { 'c3a555b04cf7e099' }
    let(:parent_id) { 'f0e71086411b1445' }
    let(:annotations) { [
      Trace::Annotation.new(Trace::Annotation::SERVER_RECV, dummy_endpoint).to_h,
      Trace::Annotation.new(Trace::Annotation::SERVER_SEND, dummy_endpoint).to_h
    ] }
    let(:span_without_parent) do
      Trace::Span.new('get', Trace::TraceId.new(span_id, nil, span_id, true, Trace::Flags::EMPTY))
    end
    let(:span_with_parent) do
      Trace::Span.new('get', Trace::TraceId.new(span_id, parent_id, span_id, true, Trace::Flags::EMPTY))
    end
    let(:timestamp) { 1452987900000000 }
    let(:duration) { 0 }
    let(:key) { 'key' }
    let(:value) { 'value' }
    let(:numeric_value) { 123 }
    let(:boolean_value) { true }

    before do
      Timecop.freeze(Time.utc(2016, 1, 16, 23, 45))
      [span_with_parent, span_without_parent].each do |span|
        annotations.each { |a| span.annotations << a }
      end
      allow(Trace).to receive(:default_endpoint).and_return(Trace::Endpoint.new('127.0.0.1', '80', 'service_name'))
    end

    describe '#to_h' do
      it 'returns a hash representation of a span' do
        expected_hash = {
          name: 'get',
          traceId: span_id,
          id: span_id,
          annotations: annotations,
          binaryAnnotations: [],
          debug: false,
          timestamp: timestamp,
          duration: duration
        }
        expect(span_without_parent.to_h).to eq(expected_hash)
        expect(span_with_parent.to_h).to eq(expected_hash.merge(parentId: parent_id))
      end
    end

    describe '#record' do
      it 'records an annotation' do
        span_with_parent.record(value)

        ann = span_with_parent.annotations[-1]
        expect(ann.value).to eq('value')
      end

      it 'converts the value to string' do
        span_with_parent.record(numeric_value)

        ann = span_with_parent.annotations[-1]
        expect(ann.value).to eq('123')
      end
    end

    describe '#record_tag' do
      it 'records a binary annotation' do
        span_with_parent.record_tag(key, value)

        ann = span_with_parent.binary_annotations[-1]
        expect(ann.key).to eq('key')
        expect(ann.value).to eq('value')
      end

      it 'converts the value to string' do
        span_with_parent.record_tag(key, numeric_value)

        ann = span_with_parent.binary_annotations[-1]
        expect(ann.value).to eq('123')
      end

      it 'does not convert the boolean value to string' do
        span_with_parent.record_tag(key, boolean_value, Trace::BinaryAnnotation::Type::BOOL)

        ann = span_with_parent.binary_annotations[-1]
        expect(ann.value).to eq(true)
      end
    end

    describe '#record_local_component' do
      it 'records a binary annotation ' do
        span_with_parent.record_local_component(value)

        ann = span_with_parent.binary_annotations[-1]
        expect(ann.key).to eq('lc')
        expect(ann.value).to eq('value')
      end
    end

  end

  describe Trace::Annotation do
    let(:annotation) { Trace::Annotation.new(Trace::Annotation::SERVER_RECV, dummy_endpoint) }

    describe '#to_h' do
      before { Timecop.freeze(Time.utc(2016, 1, 16, 23, 45)) }

      it 'returns a hash representation of an annotation' do
        expect(annotation.to_h).to eq(
          value: 'sr',
          timestamp: 1452987900000000,
          endpoint: dummy_endpoint.to_h
        )
      end
    end
  end

  describe Trace::BinaryAnnotation do
    let(:annotation) { Trace::BinaryAnnotation.new('http.path', '/', 'STRING', dummy_endpoint) }

    describe '#to_h' do
      it 'returns a hash representation of a binary annotation' do
        expect(annotation.to_h).to eq(
          key: 'http.path',
          value: '/',
          endpoint: dummy_endpoint.to_h
        )
      end
    end
  end

  describe Trace::Endpoint do
    let(:service_name) { 'service name' }
    let(:hostname) { 'z2.example.com' }

    describe '.local_endpoint' do
      it 'auto detects the hostname' do
        allow(Socket).to receive(:gethostname).and_return('z1.example.com')
        expect(Trace::Endpoint).to receive(:new).with('z1.example.com', nil, service_name, :string)
        Trace::Endpoint.local_endpoint(service_name, :string)
      end
    end

    describe '.make_endpoint' do
      context 'host lookup success' do
        before do
          allow(Socket).to receive(:getaddrinfo).with('z1.example.com', nil, :INET).
            and_return([['', '', '', '8.8.4.4']])
          allow(Socket).to receive(:getaddrinfo).with('z2.example.com', nil, :INET).
            and_return([['', '', '', '8.8.8.8']])
          allow(Socket).to receive(:getaddrinfo).with('z2.example.com', nil).
            and_return([['', '', '', '8.8.8.8']])
        end

        it 'does not translate the hostname' do
          ep = ::Trace::Endpoint.new(hostname, 80, service_name, :string)
          expect(ep.ipv4).to eq(hostname)
          expect(ep.ip_format).to eq(:string)
        end
      end
    end

    describe '#to_h' do
      context 'with service_port' do
        it 'returns a hash representation of an endpoint' do
          expect(dummy_endpoint.to_h).to eq(
            ipv4: '127.0.0.1',
            port: 9411,
            serviceName: 'DummyService'
          )
        end
      end

      context 'without service_port' do
        let(:dummy_endpoint) { Trace::Endpoint.new('127.0.0.1', nil, 'DummyService') }

        it 'returns a hash representation of an endpoint witout "port"' do
          expect(dummy_endpoint.to_h).to eq(
            ipv4: '127.0.0.1',
            serviceName: 'DummyService'
          )
        end
      end
    end
  end
end
