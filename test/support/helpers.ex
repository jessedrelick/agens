defmodule Test.Support.Helpers do
  def post_process(text) do
    cond do
      String.contains?(text, "Based on the given input") ->
        text
        |> String.split("`")
        |> Enum.at(3)

      String.contains?(text, "Here's a brief explanation of the logic behind the code:") ->
        String.first(text)

      String.contains?(text, "Here's a Python solution") ->
        String.first(text)

      String.contains?(text, "TRUE") ->
        "TRUE"

      String.contains?(text, "FALSE") ->
        "FALSE"

      true ->
        text
    end
  end

  def map_input(:first_agent, input) do
    %{
      "D" => "C",
      "E" => "D",
      "F" => "E"
    }
    |> Map.get(input, "ERROR")
  end

  def map_input(:second_agent, input) do
    %{
      "C" => "E",
      "D" => "F",
      "E" => "G"
    }
    |> Map.get(input, "ERROR")
  end

  def map_input(:verifier_agent, input) do
    if input == "G", do: "TRUE", else: input
  end

  def map_input(:tool_agent, "E"), do: "FALSE"

  def map_input(agent, input), do: "sent '#{input}' to: #{agent}"
end
