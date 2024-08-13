defmodule Agens do
  @moduledoc """
  The `Agens` module is the main entry point for Agens.

  It provides a dynamic supervisor to manage the lifecycle of Agens agents and jobs.

    ## Example
      # First, add the Agens supervisor to your application supervision tree
      Supervisor.start_link(
        [
          {Agens.Supervisor, name: Agens.Supervisor}
        ],
        strategy: :one_for_one
      )

      # Ensure the test registry is running (see `Test.Support.AgentCase`)
      iex> registry = Application.get_env(:agens, :registry)
      iex> Process.whereis(registry) |> is_pid()
      true
      iex> serving_config = %Agens.Serving.Config{
      ...>   name: :test_serving,
      ...>   serving: Test.Support.Serving.get(false)
      ...> }
      %Agens.Serving.Config{name: :test_serving, serving: serving_config.serving}
      iex> {:ok, pid} = Agens.Serving.start(serving_config)
      iex> is_pid(pid)
      true
      # Start an Agent with a name and serving module
      iex> {:ok, pid} = %Agens.Agent.Config{
      ...>   name: :test_agent,
      ...>   serving: :test_serving
      ...> }
      ...> |> Agens.Agent.start()
      iex> is_pid(pid)
      true
      iex> message = %Agens.Message{agent_name: :test_agent, input: "hello"}
      %Agens.Message{agent_name: :test_agent, input: "hello"}
      # Send a message to the Agent by agent name
      iex> Agens.Agent.message(message)
      %Agens.Message{parent_pid: nil, input: "hello", prompt: nil, result: "sent 'hello' to: test_agent", agent_name: :test_agent, serving_name: nil, job_name: nil, step_index: nil}
  """

  use DynamicSupervisor

  defmodule Message do
    @moduledoc """
    A message struct that defines the structure of a message passed between Agents, Jobs and Servings.

    ## Fields

      * `:parent_pid` - The process identifier of the parent/caller process.
      * `:input` - The input string for the message.
      * `:prompt` - The prompt string for the message.
      * `:result` - The result string for the message.
      * `:agent_name` - The name of the agent.
      * `:serving_name` - The name of the serving.
      * `:job_name` - The name of the job.
      * `:step_index` - The index of the step.
    """

    @type t :: %__MODULE__{
            parent_pid: pid(),
            input: String.t(),
            prompt: String.t() | map(),
            result: String.t(),
            agent_name: atom(),
            serving_name: atom(),
            job_name: atom(),
            step_index: non_neg_integer()
          }

    @enforce_keys []
    defstruct [
      :parent_pid,
      :input,
      :prompt,
      :result,
      :agent_name,
      :serving_name,
      :job_name,
      :step_index
    ]
  end

  @doc false
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  @spec init(any()) :: {:ok, any()}
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
