defmodule Agens.Job do
  defstruct [:name, :objective, :steps]

  defmodule Step do
    defstruct [:agent, :prompt, :conditions]
  end
end
