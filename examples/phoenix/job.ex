defmodule AgensDemo.Job do
  alias Agens.Job

  @jobs_dir Path.expand("../jobs", __DIR__)

  def load(name) do
    Path.join(@jobs_dir, "#{name}.json")
    |> File.read!()
    |> Jason.decode!()
    |> to_config()
  end

  def new_run_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def run(run_id, input) do
    config = load("industry_brief")

    with {:ok, _pid} <- Job.start(config, run_id),
         :ok <- Job.run(run_id, input, []) do
      :ok
    end
  end

  defp to_config(%{"id" => id, "nodes" => nodes} = json) do
    %Job.Config{
      id: id,
      starting_node_id: Map.get(json, "first_node"),
      description: Map.get(json, "description"),
      max_retries: Map.get(json, "max_retries", 3),
      nodes:
        Map.new(nodes, fn {node_id, node} ->
          {node_id,
           %Job.Node{
             agent_id: Map.get(node, "agent_id"),
             serving: node |> Map.fetch!("serving") |> String.to_atom(),
             objective: Map.get(node, "objective"),
             tools: node["tools"],
             resources: node["resources"] && Enum.map(node["resources"], &resource_from_name/1)
           }}
        end)
    }
  end

  def load_outputs(name) do
    Path.join(@jobs_dir, "#{name}.json")
    |> File.read!()
    |> Jason.decode!()
    |> parse_outputs()
  end

  defp parse_outputs(json) do
    (json["outputs"] || [])
    |> Enum.map(fn o ->
      %Agens.Router.Output{
        key: o["key"],
        type: o["type"],
        description: o["description"],
        meta: o["meta"] && Map.new(o["meta"], fn {k, v} -> {String.to_atom(k), v} end)
      }
    end)
  end

  defp resource_from_name(name) do
    %Agens.Resource{uri: "agens://resources/#{name}", name: name}
  end

end
