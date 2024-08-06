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
end
