defmodule Agens.Job.Sub do
  @moduledoc """
  Describes a sub-Job to be started in place of a Serving call on a Job Node.

  A `Sub` is returned from the `c:Agens.Backend.sub/2` callback and carries the
  configuration and run identifiers needed to nest a Job inside a parent Job.

  ## Fields

    * `:config` - The `Agens.Job.Config` defining the sub-Job to run.
    * `:run_id` - The unique run identifier of the sub-Job instance.
    * `:parent_run_id` - The run identifier of the enclosing parent Job. Set by the runtime.
    * `:parent_node_message` - The `Agens.Message` of the parent Node that triggered the sub-Job. Set by the runtime.
  """

  @type t :: %__MODULE__{
          config: Agens.Job.Config.t(),
          run_id: binary(),
          parent_run_id: binary() | nil,
          parent_node_message: Agens.Message.t() | nil
        }

  @enforce_keys [:config]
  defstruct [:config, :run_id, :parent_run_id, :parent_node_message]
end
