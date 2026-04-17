defmodule Agens.Metrics do
  import Telemetry.Metrics

  @durations [[0, 50, 100, 200, 500] | Enum.to_list(1000..10000//1000)] |> :lists.flatten()

  def metrics() do
    [
      counter("agens.serving.start", event_name: [:agens, :serving, :start], tags: []),
      counter("agens.serving.enqueue", event_name: [:agens, :serving, :enqueue], tags: []),
      counter("agens.serving.stop", event_name: [:agens, :serving, :stop], tags: []),
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
      counter("agens.tool.call", event_name: [:agens, :tool, :call], tags: [:name]),
      counter("agens.resource.load", event_name: [:agens, :resource, :load], tags: [:name]),
      distribution("agens.serving.result.duration",
        event_name: [:agens, :serving, :result, :stop],
        reporter_options: [buckets: @durations],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:name]
      )
    ]
  end
end
