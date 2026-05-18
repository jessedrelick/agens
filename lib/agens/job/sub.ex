defmodule Agens.Job.Sub do
  @moduledoc false

  @type t :: %__MODULE__{
          config: Agens.Job.Config.t(),
          run_id: binary(),
          parent_run_id: binary() | nil,
          parent_node_message: Agens.Message.t() | nil
        }

  @enforce_keys [:config]
  defstruct [:config, :run_id, :parent_run_id, :parent_node_message]
end
