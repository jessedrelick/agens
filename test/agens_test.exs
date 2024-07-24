defmodule AgensTest do
  use ExUnit.Case
  doctest Agens

  test "greets the world" do
    assert Agens.hello() == :world
  end
end
