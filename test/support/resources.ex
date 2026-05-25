defmodule Test.Support.Resources do
  def resource_def() do
    %Agens.Resource{
      uri: "test://resources/context",
      name: "context",
      description: "Test resource providing context"
    }
  end

  def resource_def(:no_content) do
    %Agens.Resource{
      uri: "test://resources/empty",
      name: "empty",
      description: "Test resource with no content loaded"
    }
  end

  def resource_content("test://resources/context"),
    do: "This is test resource context content."

  def resource_content(_), do: nil
end
