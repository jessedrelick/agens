defmodule Test.Support.Serving do
  use GenServer

  def run(prompt) do
    GenServer.call(__MODULE__, {:run, prompt})
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def init(opts) do
    {:ok, opts}
  end

  def handle_call({:run, _prompt, input}, _, state) do
    agent = Keyword.get(state, :config)
    text = map_input(agent.name, input)
    output = %{results: [%{text: text}]}
    {:reply, output, state}
  end

  defp map_input(:first_agent, input) do
    %{
      "D" => "C",
      "E" => "D",
      "F" => "E"
    }
    |> Map.get(input, "ERROR")
  end

  defp map_input(:second_agent, input) do
    %{
      "C" => "E",
      "D" => "F",
      "E" => "G"
    }
    |> Map.get(input, "ERROR")
  end

  defp map_input(:verifier_agent, input) do
    if input == "G", do: "TRUE", else: "FALSE"
  end

  defp map_input(:tool_agent, "E"), do: "FALSE"
end
