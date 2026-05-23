defmodule Agens.RouterTest do
  use ExUnit.Case, async: true

  alias Agens.{Message, Router}
  alias Agens.Router.Output

  defmodule TestRouter do
    use Agens.Router

    @impl Agens.Router
    def outputs(%Message{job_id: "scored_job"}) do
      [
        %Output{key: "score", type: "int"},
        %Output{key: "pass", type: "bool"}
      ]
    end

    def outputs(%Message{}), do: []

    @impl Agens.Router
    def resolve(%Message{}, outputs) do
      case Enum.find(outputs, &(&1.key == "pass")) do
        %Output{value: true} -> [{:route, "next_node", 1}]
        _ -> [:retry]
      end
    end
  end

  # ===========================================================================
  # parse_next/1
  # ===========================================================================

  describe "parse_next/1" do
    test "route" do
      assert Router.parse_next([%{"type" => "route", "value" => "node_a"}]) ==
               [{:route, "node_a", 1}]
    end

    test "yield" do
      assert Router.parse_next([%{"type" => "yield", "value" => "node_b"}]) ==
               [{:yield, "node_b"}]
    end

    test "job" do
      assert Router.parse_next([%{"type" => "sub", "value" => "other_job"}]) ==
               [{:sub, "other_job"}]
    end

    test "end" do
      assert Router.parse_next([%{"type" => "end"}]) == [:end]
    end

    test "retry" do
      assert Router.parse_next([%{"type" => "retry"}]) == [:retry]
    end

    test "unknown type is filtered out" do
      assert Router.parse_next([%{"type" => "unknown", "value" => "x"}]) == []
    end

    test "mixed valid and invalid" do
      input = [
        %{"type" => "route", "value" => "node_a"},
        %{"type" => "unknown"},
        %{"type" => "end"}
      ]

      assert Router.parse_next(input) == [{:route, "node_a", 1}, :end]
    end

    test "empty list" do
      assert Router.parse_next([]) == []
    end
  end

  # ===========================================================================
  # route/1 and route/2
  # ===========================================================================

  describe "route/1" do
    test "calls resolve when all output keys present" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message) == [{:route, "next_node", 1}]
    end

    test "returns retry when output keys missing" do
      message = %Message{input: "test", job_id: "scored_job", outputs: %{"score" => 9}}

      assert TestRouter.route(message) == [:retry]
    end

    test "returns retry when outputs is nil" do
      message = %Message{input: "test", job_id: "scored_job", outputs: nil}

      assert TestRouter.route(message) == [:retry]
    end

    test "calls resolve with empty outputs when no outputs defined" do
      message = %Message{input: "test", job_id: "no_outputs_job", outputs: %{}}

      assert TestRouter.route(message) == [:retry]
    end
  end

  describe "route/2" do
    test "uses dynamic_next when non-empty and valid" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "route", "value" => "override_node"}]

      assert TestRouter.route(message, dynamic) == [{:route, "override_node", 1}]
    end

    test "falls through to route/1 when dynamic_next is empty list" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message, []) == [{:route, "next_node", 1}]
    end

    test "falls through to route/1 when dynamic_next is nil" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message, nil) == [{:route, "next_node", 1}]
    end

    test "falls through to route/1 when all dynamic_next entries are invalid" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "unknown"}, %{"type" => "also_unknown"}]

      assert TestRouter.route(message, dynamic) == [{:route, "next_node", 1}]
    end

    test "dynamic_next overrides even when static routing would succeed" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "end"}]

      assert TestRouter.route(message, dynamic) == [:end]
    end
  end
end
