# Mongo Instrumentation contributed by Alexey Palazhchenko
DependencyDetection.defer do

  depends_on do
    defined?(::Mongo) and not NewRelic::Control.instance['disable_mongodb']
  end

  executes do
    ::Mongo::Connection.class_eval do
      include NewRelic::Agent::MethodTracer

      def instrument_with_newrelic_trace(name, payload = {}, &blk)
        collection = payload[:collection]
        if collection == '$cmd'
          f = payload[:selector].first
          name, collection = f if f
        end

        trace_execution_scoped(["Database/#{collection}/#{name}", "ActiveRecord/all"]) do
          t0 = Time.now
          res = instrument_without_newrelic_trace(name, payload, &blk)
          NewRelic::Agent.instance.transaction_sampler.notice_sql(payload.inspect, nil, (Time.now - t0).to_f)
          res
        end
      end

      alias_method :instrument_without_newrelic_trace, :instrument
      alias_method :instrument, :instrument_with_newrelic_trace
    end

    ::Mongo::Cursor.class_eval do
      include NewRelic::Agent::MethodTracer

      def refresh_with_newrelic_trace
        return if send_initial_query || @cursor_id.zero? # don't double report the initial query

        trace_execution_scoped(["Database/#{collection.name}/refresh", "ActiveRecord/all"]) do
          refresh_without_newrelic_trace
        end
      end
      alias_method :refresh_without_newrelic_trace, :refresh
      alias_method :refresh, :refresh_with_newrelic_trace
      add_method_tracer :close, 'Database/#{collection.name}/close'
    end
  end

end
