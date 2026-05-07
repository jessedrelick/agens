defmodule Agens.AgensTest do
  use ExUnit.Case, async: false
  # doctest Agens

  describe "backends/0" do
    test "returns a list of backend modules from application config" do
      backends = Agens.backends()
      assert is_list(backends)
      assert length(backends) > 0
      assert Enum.all?(backends, &is_atom/1)
    end
  end

  describe "backends/2" do
    test "applies the given function to all configured backends and returns results" do
      results = Agens.backends(:sub, [self(), "some_job"])
      assert is_list(results)
      assert length(results) == length(Agens.backends())
    end
  end
end
