defmodule Agens.ResourceTest do
  use ExUnit.Case, async: true

  alias Agens.Resource

  test "from_map/1 builds a Resource from a string-keyed map" do
    result =
      Resource.from_map(%{
        "uri" => "test://example",
        "name" => "Test Resource",
        "description" => "A test description",
        "content" => "Some content"
      })

    assert %Resource{} = result
    assert result.uri == "test://example"
    assert result.name == "Test Resource"
    assert result.description == "A test description"
    assert result.content == "Some content"
  end

  test "from_map/1 allows nil description and content" do
    result = Resource.from_map(%{"uri" => "test://minimal", "name" => "Minimal"})

    assert result.uri == "test://minimal"
    assert result.name == "Minimal"
    assert result.description == nil
    assert result.content == nil
  end
end
