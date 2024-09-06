defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.

  `Agens.Supervisor` starts a `DynamicSupervisor` for managing `Agens.Agent`, `Agens.Serving`, and `Agens.Job` processes.

  In order to use `Agens` simply add `Agens.Supervisor` to your application supervision tree:

  ```
  Supervisor.start_link(
    [
      {Agens.Supervisor, name: Agens.Supervisor}
    ],
    strategy: :one_for_one
  )
  ```

  ### Options
    * `:prompts` (`map`) - The default prompt prefixes can be overriden with this option. Each `Agens.Serving.Config` can also override the defaults on a per-serving basis.

  See the [README.md](README.md#configuration) for more info.
  """
  use Supervisor

  @default_prompts %{
    prompt:
      {"Agent", "You are a specialized agent with the following capabilities and expertise"},
    identity:
      {"Identity", "You are a specialized agent with the following capabilities and expertise"},
    context: {"Context", "The purpose or goal behind your tasks are to"},
    constraints:
      {"Constraints", "You must operate with the following constraints or limitations"},
    examples: {"Examples", "You should consider the following examples before returning results"},
    reflection:
      {"Reflection", "You should reflect on the following factors before returning results"},
    instructions:
      {"Tool Instructions",
       "You should provide structured output for function calling based on the following instructions"},
    objective: {"Step Objective", "The objective of this step is to"},
    description: {"Job Description", "This is part of multi-step job to achieve the following"},
    input: {"Input", "The following is the actual input from the user, system or another agent"}
  }
  @default_opts [prompts: @default_prompts]

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :supervisor
    }
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    override = Keyword.get(args, :opts, [])
    opts = Keyword.merge(@default_opts, override)

    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  @spec init(keyword()) ::
          {:ok,
           {:supervisor.sup_flags(),
            [:supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
          | :ignore
  def init(opts) do
    children = [
      {Agens, name: Agens, opts: opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
