defmodule AgensDemo.History do
  @base_dir "examples/tmp"

  def write(%Agens.Message{} = message) do
    dir = run_dir(message.run_id)
    File.mkdir_p!(dir)

    index = next_index(dir)
    node_id = to_string(message.node_id)
    filename = :io_lib.format("~4..0B_~s.json", [index, node_id]) |> IO.chardata_to_string()

    entry = %{
      run_id: message.run_id,
      node_id: node_id,
      thread_id: message.thread_id,
      input: message.input,
      result: message.result,
      outputs: message.outputs,
      inserted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    path = Path.join(dir, filename)
    File.write!(path, Jason.encode!(entry, pretty: true))
    {:ok, path}
  end

  def load(run_id) do
    dir = run_dir(run_id)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.sort()
        |> Enum.map(fn file ->
          dir
          |> Path.join(file)
          |> File.read!()
          |> Jason.decode!(keys: :atoms)
        end)

      {:error, _} ->
        []
    end
  end

  def runs do
    case File.ls(@base_dir) do
      {:ok, dirs} -> Enum.sort(dirs)
      {:error, _} -> []
    end
  end

  defp run_dir(run_id), do: Path.join(@base_dir, to_string(run_id))

  defp next_index(dir) do
    case File.ls(dir) do
      {:ok, files} -> length(files) + 1
      {:error, _} -> 1
    end
  end
end
