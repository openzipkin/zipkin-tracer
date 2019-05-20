module ZipkinTracer
  # Useful methods on the Application we are instrumenting
  class Application
    # Determines if our framework knows whether the request will be routed to a controller
    def self.routable_request?(env)
      return true unless defined?(Rails) # If not running on a Rails app, we can't verify if it is invalid
      path_info = env[Rack::PATH_INFO] || ""
      http_method = env[Rack::REQUEST_METHOD]
      Rails.application.routes.recognize_path(path_info, method: http_method)
      true
    rescue ActionController::RoutingError
      false
    end

    def self.route(env)
      return nil unless defined?(Rails)
      stub_env = {
        "PATH_INFO" => env[Rack::PATH_INFO],
        "REQUEST_METHOD" => env[Rack::REQUEST_METHOD]
      }
      req = Rack::Request.new(stub_env)
      # Returns a string like /some/path/:id
      Rails.application.routes.router.recognize(req) do |route|
        return route.path.spec.to_s
      end
    rescue
      nil
    end

    def self.logger
      if defined?(Rails.logger)
        Rails.logger
      else
        Logger.new(STDOUT)
      end
    end

    def self.config(app)
      if app.respond_to?(:config) && app.config.respond_to?(:zipkin_tracer)
        app.config.zipkin_tracer
      else
        {}
      end
    end
  end
end
