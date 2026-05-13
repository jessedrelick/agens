defmodule Agens.Backend do
  alias Agens.{Message, Resource}

  @type job_id :: binary()
  @type run_id :: binary()
  @type node_id :: any()
  @type status :: atom()
  @type tool_call :: %{
          required(:name) => binary(),
          required(:arguments) => map(),
          required(:result) => any() | nil,
          required(:error) => binary() | nil
        }

  @callback start(pid(), job_id(), run_id()) :: :ok
  @callback status(pid(), run_id(), status()) :: :ok
  @callback complete(pid(), run_id()) :: :ok
  @callback error(pid(), Message.t(), any()) :: :ok
  @callback node_started(pid(), Message.t()) :: :ok
  @callback node_retry(pid(), Message.t()) :: :ok
  @callback node_result(pid(), Message.t()) :: :ok
  @callback tool_call(pid(), Message.t(), tool_call()) :: :ok
  @callback resource_load(pid(), Message.t(), Resource.t()) :: :ok
  @callback prompt(Message.t()) :: :ok
  @callback yield_wait(pid(), Message.t(), integer(), integer()) :: :ok
  @callback yield_done(pid(), Message.t(), integer()) :: :ok
  @callback sub(pid(), job_id()) :: Agens.Job.Sub.t() | nil
end
