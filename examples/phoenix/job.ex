defmodule AgensDemo.Job do
  alias Agens.Job

  @jobs_dir Path.expand("../jobs", __DIR__)

  def load(name) do
    json =
      Path.join(@jobs_dir, "#{name}.json")
      |> File.read!()
      |> Jason.decode!()

    edges_json =
      Path.join(@jobs_dir, "#{name}_edges.json")
      |> File.read!()
      |> Jason.decode!()

    config = to_config(json)
    Application.put_env(:agens_demo, {:job_outputs, config.id}, parse_outputs(json))
    Application.put_env(:agens_demo, {:job_edges, config.id}, parse_edges(edges_json))
    {config, Map.fetch!(json, "first_node")}
  end

  def new_run_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def run(run_id, input) do
    {config, first_node} = Application.fetch_env!(:agens_demo, :job)

    with {:ok, _pid} <- Job.start(config, run_id),
         :ok <- Job.run(run_id, input, first_node, []) do
      :ok
    end
  end

  defp to_config(%{"id" => id, "nodes" => nodes} = json) do
    %Job.Config{
      id: id,
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

  defp parse_outputs(json) do
    (json["outputs"] || [])
    |> Enum.map(fn o ->
      %Agens.Router.Output{
        key: o["key"],
        type: o["type"],
        description: o["description"],
        values: o["values"],
        meta: o["meta"] && Map.new(o["meta"], fn {k, v} -> {String.to_atom(k), v} end)
      }
    end)
  end

  defp parse_edges(json) do
    Map.new(json, fn {node_id, node_edges} ->
      edges =
        Enum.map(node_edges, fn e ->
          %AgensDemo.AgensRouter.Edge{
            type: (e["type"] || "route") |> String.to_atom(),
            to_id: e["to_id"],
            count: e["count"] || 1,
            conditions: parse_conditions(e["conditions"] || [])
          }
        end)

      {node_id, edges}
    end)
  end

  defp resource_from_name(name) do
    %Agens.Resource{uri: "agens://resources/#{name}", name: name}
  end

  defp parse_conditions(conditions) do
    Enum.map(conditions, fn c ->
      %Agens.Router.Condition{key: c["key"], op: c["op"], value: c["value"]}
    end)
  end
end
