defmodule Agens.MetricsTest do
  use ExUnit.Case, async: true

  alias Agens.Metrics

  test "metrics/0 returns a non-empty list" do
    metrics = Metrics.metrics()
    assert is_list(metrics)
    assert length(metrics) > 0
  end

  test "metrics/0 includes serving metrics" do
    names = Metrics.metrics() |> Enum.map(& &1.name)
    assert [:agens, :serving, :start] in names
    assert [:agens, :serving, :enqueue] in names
    assert [:agens, :serving, :stop] in names
    assert [:agens, :serving, :result] in names
    assert [:agens, :serving, :result, :exception] in names
    assert [:agens, :serving, :result, :duration] in names
  end

  test "metrics/0 includes job metrics" do
    names = Metrics.metrics() |> Enum.map(& &1.name)
    assert [:agens, :job, :start] in names
    assert [:agens, :job, :run] in names
    assert [:agens, :job, :stop] in names
    assert [:agens, :job, :status] in names
    assert [:agens, :job, :complete] in names
    assert [:agens, :job, :end] in names
    assert [:agens, :job, :yield_wait] in names
    assert [:agens, :job, :yield_done] in names
    assert [:agens, :job, :error] in names
  end

  test "metrics/0 includes node metrics" do
    names = Metrics.metrics() |> Enum.map(& &1.name)
    assert [:agens, :node, :start] in names
    assert [:agens, :node, :result] in names
    assert [:agens, :node, :retry] in names
  end

  test "metrics/0 includes sub-job metrics" do
    names = Metrics.metrics() |> Enum.map(& &1.name)
    assert [:agens, :sub, :start] in names
    assert [:agens, :sub, :handle] in names
    assert [:agens, :sub, :done] in names
    assert [:agens, :sub, :error] in names
  end

  test "metrics/0 includes tool and resource metrics" do
    names = Metrics.metrics() |> Enum.map(& &1.name)
    assert [:agens, :tool, :call] in names
    assert [:agens, :tool, :call, :exception] in names
    assert [:agens, :tool, :call, :duration] in names
    assert [:agens, :resource, :load] in names
    assert [:agens, :resource, :load, :exception] in names
    assert [:agens, :resource, :load, :duration] in names
  end
end
