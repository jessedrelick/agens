defmodule AgensRouter.Edge do
  @type t :: %__MODULE__{
          type: :route | :fallback | :yield | :end | :retry,
          to_id: any(),
          count: pos_integer(),
          conditions: list(AgensRouter.Condition.t())
        }

  defstruct type: :route, to_id: nil, count: 1, conditions: []
end
