# 0.39.3
* Protect Faraday and Excon middlewares against adding them twice.

# 0.39.2
* Make Faraday 0.13 the minimum requirement.

# 0.39.1
* Duplicate rack environment strings so that applications that depend on this call only happening once don't break.

# 0.39.0
* Allow clients to provide an explicit timestamp when starting and stopping spans.

# 0.38.0
* Add RabbitMQ sender.

# 0.37.0
* Add an `async` option to the HTTP and SQS senders.
* Allow the `logger` option to be provided.
* Add the TraceWrapper utility class.

# 0.36.2
* Cleanup the gemspec. No code changes.

# 0.36.1
* Bugfix: Prevent uninitialized constant AsyncHttpApiClient::ZipkinHttpSender error

# 0.36.0
* Add ZipkinSqsSender to send spans via Amazon SQS
* Rename ZipkinJsonTracer to ZipkinHttpSender and rename others to replace the term "tracer" with "sender"

# 0.35.1
* Fix bug with Rails 5.1 when calling recognize_path with a nil path

# 0.35.0
* removes record_on_server_receive option
* records status_code and method on all server receive events.

# 0.34.0
* Whitelist plugin ensure a request is traced even if it is not routable
* Gem requires Ruby > 2.3.0. In practice this was true already.

# 0.33.0
* Switch to Zipkin v2 span format

# 0.32.4
* Remove the ':service_port' configuration.
* Fix 'sa' annotation encoding.

# 0.32.3
* Fix bug using trace generator.

# 0.32.2
* Recover the old Trace.id logic but based not the new API. Again, for compatibility.

# 0.32.1
* Delete added parameter to trace.next_id

# 0.32.0
* Restore Trace.id for now as software needs to migrate out of it.

# 0.31.0
* Remove dependency from finagle-thrift
* Use http.url instead of http.uri

# 0.30.0
* Add 'http.method' to client annotations

# 0.29.1
* Patch abstract route to work with Grape

# 0.29.0
* Add abstract route to span name
* Fix not to raise "NoMethodError" for Rails:Module

# 0.28.0
* Add the `:trace_id_128bit` configuration option.

# 0.27.2.1
* Update version.rb to fix checksum mismatch on RubyGems.org
* Add `condition` on Travis CI deployment

# 0.27.2
* Convert trace values to string

# 0.27.1
* Rescue connection errors when sending information to Zipkin fails

# 0.27.0
* Add tagging of errors for Faraday and Excon.

# 0.26.0
* Add sidekiq worker tracing.

# 0.25.0
* Fix pass kafka producer to rack middleware

# 0.24.0
* Fix Pass and use the span in annotate_plugin

# 0.23.0
* Fix Excon middleware span duration
* Add `start_span` and `end_span` to the Null tracer

# 0.22.0
* Add the `:record_on_server_receive` configuration option.

# 0.21.2
* Bugfix: Guard against tracer not set in Faraday and Excon middlewares

# 0.21.1
* Bugfix: better guard against nil response in the Excon middleware

# 0.21.0
* Added an Excon middleware

# 0.20.1
* Bugfix: Properly handle the `sampled_as_boolean` configuration option

# 0.20.0
* Bugfix: The Faraday middleware does not leave in the container any generated Id
* Added TraceContainer and TraceGenerator to provide easier abstractions to interact with this library

# 0.19.1
* Limits the required headers to x_b3_trace_id and x_b3_span_id as per spec.

# 0.19.0
* Propagates the X-B3-Sampled in the same form it receives it (boolean or 1/0)
* Adds a configuration option to allow a service to emit boolean or numbers for the X-B3-Sampled header

# 0.18.6
* Passes HTTP Method to recognize_path

# 0.18.5
* `NullTracer` has a noop `flush!` method.
* Spans from `local_component_span` will be named according to `local_component_value` over `lc`.

# 0.18.4
* Uses http.path to annotate paths instead of http.uri.

# 0.18.3
* Ensures ip addresses for all hostnames are resolved, solves issue with docker hostnames

# 0.18.2
* Remove nil parentId from zipkin span payload.

# 0.18.1
* Turn the ZipkinTracer::FaradayHandler::B3_HEADERS constant into a private method

# 0.18.0
* Adds the :log_tracing option to explicitly use the logger tracer.
* Logger classes can not be passed via the configuration file (never worked correctly).
* Logger tracer logs in JSON format for easy analysis by other tools.

# 0.17.0
Adds a :producer configuration key as an alternative to Hermann as Kafka client.

# 0.16.0
* Remove the scribe tracer.
* Use sucker_punch 2.x. The main feature is the dependency on concurrent-ruby instead of celluloid.

# 0.15.1
* Less strict dependency on Rack. Allows to use Rails 5.

# 0.15.0
* Hostname resolution done asyncronously for the JSON tracer

# 0.14.1
* Access to the tracer when we need it and not before.

# 0.14.0
* Adds a logger kind of tracer.

# 0.13.2
* Move record methods in TraceClient to Span
* Relocate definition of constant variables

# 0.13.1
* Check the config entry is not blank when infering adapters

# 0.13.0
* Remove support for buffering. It was broken anyways.

# 0.12.2
* Make local tracing method (ZipkinTracer::TraceClient.local_component_span) returns the result of block

# 0.12.1
* Allow nesting of local tracing spans

# 0.12.0
* Add local tracing, fix flushing, add timestamp and duration to span

# 0.11.0
* Use local spans instead of thread-safe variables to improve performance
* Add new `with_new_span` method to the tracer api to allow creating custom spans

# 0.10.3
* Avoid requiring finagle-thrift when possible to avoid a hard dependency on Thrift

# 0.10.2
* Add faraday as a dependency

# 0.10.1
* Performance optimization: Do not create tracing related objects in the Faraday middleware if we
are not sampling.
* Fix benchmark Rake task so it uses the proper Faraday middlewares

# 0.10.0
* Always create trace IDs even when the trace  will not be sent to zipkin (other parts of the app may use them).
* Bugfix: Tracer is now Threadsafe
* Development improvement: Benchmark Rake task to help finding performance issues

# 0.9.1
* Make Scribe actually optional by inspecting the conf first and requiring after.

# 0.9.0
* Add a JSON tracer (ZipkinJsonTracer).

# 0.8.1
* Set caller service name using domain environment variable. If the value
is not set, it will fall back to the configuration file default.

# 0.8.0
* To proper follow the correct spec, now the annotations cr/cs set the local service as servicename
* Added a 'sa' annotation to indicate the remote service servicename

# 0.7.3
* Send method name (get, post, etc) as lowercase (zipkin > 1.22 expect them lowercase)

# 0.7.2
* Rescue possible errors when lookup of the hostname fails

# 0.7.1
* Remove Scribe from direct dependencies list

# 0.7
* The ruby client does not wait to receive ACK from the collector. Just send traces
* Connecting to the collector now happens in a different thread
* The server annotations will not add information about the URL hit if hit by a zipkin enabled client

# 0.6.3
* Properly pop the Id from the traces stacks when finishing the Faraday tracer

# 0.6.2
* Do not trace requests if the current application will not serve them.

# 0.6.1
* Relax constraint on Rack from ~> 1.6 to ~> 1.3

# 0.6
* New configuration option :logger to setup a logger for error messages
* The Zipkin Rack middleware will not raise an error if sending information to Zipkin raises an error

# 0.5.1
* The Zipkin Rack middleware will not raise an error if sending information to Zipkin raises an error
* Integration specs to make sure information is properly passed when using Rack middleware together with Faraday's

# 0.5.0
* Added Faraday middleware to the repo

# 0.4.0
* Use Thread safe Finagle version to store the traces
