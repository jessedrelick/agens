defmodule Agens.Metrics do
  @moduledoc """
  `Telemetry.Metrics` definitions for the events emitted by Agens.

  The list returned by `metrics/0` is intended to be supplied to a
  `Telemetry.Metrics.Reporter` (for example `TelemetryMetricsPrometheus`,
  `TelemetryMetricsStatsd`, or your own reporter) in your application's
  supervision tree.

  ## Wiring into a parent application

  Add a `Telemetry.Metrics.Supervisor` (or reporter of your choice) to your
  application's supervision tree and feed it `Agens.Metrics.metrics/0`:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Agens.Supervisor, name: Agens.Supervisor},
            {TelemetryMetricsPrometheus, metrics: Agens.Metrics.metrics()}
            # ...your own children
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  To combine Agens metrics with metrics from your own app:

      def metrics do
        Agens.Metrics.metrics() ++ my_app_metrics()
      end

  ## Event coverage

  Metrics are emitted for the following event prefixes:

    * `[:agens, :serving, ...]` - Serving lifecycle, sub dispatch, enqueue, and result duration /
      exceptions (via `:telemetry.span/3`).
    * `[:agens, :job, ...]` - Job lifecycle, status changes, retries, yields, sub-jobs and errors.
    * `[:agens, :node, ...]` - Per-Node start, result, and retry events.
    * `[:agens, :tool, :call, ...]` - Tool calls with duration and exception coverage (span).
    * `[:agens, :resource, :load, ...]` - Resource loads with duration and exception coverage (span).
  """

  import Telemetry.Metrics

  @durations [[0, 50, 100, 200, 500] | Enum.to_list(1000..10000//1000)] |> :lists.flatten()

  @doc """
  Returns the list of `Telemetry.Metrics` definitions for all Agens events.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics() do
    [
      # Serving lifecycle
      counter("agens.serving.start", event_name: [:agens, :serving, :start], tags: []),
      counter("agens.serving.enqueue", event_name: [:agens, :serving, :enqueue], tags: []),
      counter("agens.serving.sub", event_name: [:agens, :serving, :sub], tags: []),
      counter("agens.serving.stop", event_name: [:agens, :serving, :stop], tags: []),

      # Serving inference (span)
      counter("agens.serving.result",
        event_name: [:agens, :serving, :result, :stop],
        tags: [:name]
      ),
      counter("agens.serving.result.exception",
        event_name: [:agens, :serving, :result, :exception],
        tags: [:name]
      ),
      distribution("agens.serving.result.duration",
        event_name: [:agens, :serving, :result, :stop],
        reporter_options: [buckets: @durations],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:name]
      ),

      # Job lifecycle
      counter("agens.job.start", event_name: [:agens, :job, :start], tags: []),
      counter("agens.job.run", event_name: [:agens, :job, :run], tags: []),
      counter("agens.job.stop", event_name: [:agens, :job, :stop], tags: []),
      counter("agens.job.status", event_name: [:agens, :job, :status], tags: [:status]),
      counter("agens.job.retry", event_name: [:agens, :job, :retry], tags: [:retry]),
      counter("agens.job.complete", event_name: [:agens, :job, :complete], tags: []),
      counter("agens.job.sub", event_name: [:agens, :job, :sub], tags: []),
      counter("agens.job.end", event_name: [:agens, :job, :end], tags: []),
      counter("agens.job.yield_wait", event_name: [:agens, :job, :yield_wait], tags: []),
      counter("agens.job.yield_done", event_name: [:agens, :job, :yield_done], tags: []),
      counter("agens.job.error", event_name: [:agens, :job, :error], tags: []),

      # Node lifecycle
      counter("agens.node.start", event_name: [:agens, :node, :start], tags: []),
      counter("agens.node.result", event_name: [:agens, :node, :result], tags: []),
      counter("agens.node.retry", event_name: [:agens, :node, :retry], tags: [:retry]),

      # Tool calls (span)
      counter("agens.tool.call",
        event_name: [:agens, :tool, :call, :stop],
        tags: [:name]
      ),
      counter("agens.tool.call.exception",
        event_name: [:agens, :tool, :call, :exception],
        tags: [:name]
      ),
      distribution("agens.tool.call.duration",
        event_name: [:agens, :tool, :call, :stop],
        reporter_options: [buckets: @durations],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:name]
      ),

      # Resource loads (span)
      counter("agens.resource.load",
        event_name: [:agens, :resource, :load, :stop],
        tags: [:name]
      ),
      counter("agens.resource.load.exception",
        event_name: [:agens, :resource, :load, :exception],
        tags: [:name]
      ),
      distribution("agens.resource.load.duration",
        event_name: [:agens, :resource, :load, :stop],
        reporter_options: [buckets: @durations],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:name]
      )
    ]
  end
end
