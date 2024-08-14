defmodule Agens do
  @moduledoc """
  Agens is used to create multi-agent workflows with language models.

  It is made up of the following core entities:

  - `Agens.Serving` - used to interact with language models
  - `Agens.Agent` - used to interact with servings in a specialized manner
  - `Agens.Job` - used to define multi-agent workflows

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
      %Agens.Message{parent_pid: nil, input: "hello", prompt: nil, result: "STUB RUN", agent_name: :test_agent, serving_name: nil, job_name: nil, step_index: nil}
  """

  defmodule Message do
    @moduledoc """
    The Message struct defines the details of a message passed between Agents, Jobs and Servings.

    ## Fields

      * `:parent_pid` - The process identifier of the parent/caller process.
      * `:input` - The input string for the message.
      * `:prompt` - The prompt string or `Agens.Agent.Prompt` struct for the message.
      * `:result` - The result string for the message.
      * `:agent_name` - The name of the `Agens.Agent`.
      * `:serving_name` - The name of the `Agens.Serving`.
      * `:job_name` - The name of the `Agens.Job`.
      * `:job_description` - The description of the `Agens.Job` to be added to the LM prompt.
      * `:step_index` - The index of the `Agens.Job.Step`.
      * `:step_objective` - The objective of the `Agens.Job.Step` to be added to the LM prompt.
    """

    @type t :: %__MODULE__{
            parent_pid: pid() | nil,
            input: String.t() | nil,
            prompt: String.t() | Agens.Agent.Prompt.t() | nil,
            result: String.t() | nil,
            agent_name: atom() | nil,
            serving_name: atom() | nil,
            job_name: atom() | nil,
            job_description: String.t() | nil,
            step_index: non_neg_integer() | nil,
            step_objective: String.t() | nil
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
      :job_description,
      :step_index,
      :step_objective
    ]
  end

  use DynamicSupervisor

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
