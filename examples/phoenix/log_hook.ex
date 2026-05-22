defmodule AgensDemo.LogHook do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:logs, [])
      |> attach_hook(:log, :handle_info, &log/2)

    {:cont, socket}
  end

  def log({:job_started, _run_id}, socket) do
    {:cont, append_log(socket, :job_started)}
  end

  def log({:job_status, _run_id, status}, socket) do
    {:cont, append_log(socket, :job_status, %{status: status})}
  end

  def log({:job_complete, _run_id}, socket) do
    {:cont, append_log(socket, :job_complete)}
  end

  def log({:job_error, message, err}, socket) do
    {:cont, append_log(socket, :job_error, %{agent_id: message.agent_id, error: inspect(err)})}
  end

  def log({:node_started, message}, socket) do
    {:cont, append_log(socket, :node_started, %{agent_id: message.agent_id})}
  end

  def log({:node_retry, message}, socket) do
    {:cont, append_log(socket, :node_retry, %{agent_id: message.agent_id, attempt: message.retries})}
  end

  def log({:node_result, message}, socket) do
    {:cont, append_log(socket, :node_result, %{agent_id: message.agent_id})}
  end

  def log({:tool_call, _message, %{error: nil, tool: %{name: tool_name}}}, socket) do
    {:cont, append_log(socket, :tool_call, %{tool: tool_name})}
  end

  def log({:tool_call, _message, %{error: error, tool: %{name: tool_name}}}, socket) do
    {:cont, append_log(socket, :tool_error, %{tool: tool_name, error: error})}
  end

  def log({:resource_load, _message, %{error: nil, resource: resource}}, socket) do
    {:cont,
     append_log(socket, :resource_load, %{
       name: resource.name,
       uri: resource.uri
     })}
  end

  def log({:resource_load, _message, %{error: error, resource: resource}}, socket) do
    {:cont,
     append_log(socket, :resource_error, %{
       name: resource.name,
       uri: resource.uri,
       error: error
     })}
  end

  def log({:yield_wait, message, total, ready}, socket) do
    {:cont, append_log(socket, :yield_wait, %{agent_id: message.agent_id, ready: ready, total: total})}
  end

  def log({:yield_done, message, total}, socket) do
    {:cont, append_log(socket, :yield_done, %{agent_id: message.agent_id, total: total})}
  end

  def log(_msg, socket), do: {:cont, socket}

  defp append_log(%{assigns: %{logs: logs}} = socket, event) when is_atom(event) do
    assign(socket, :logs, ["[Agens] #{event}" | logs])
  end

  defp append_log(%{assigns: %{logs: logs}} = socket, event, attrs) when is_atom(event) do
    pairs = Enum.map_join(attrs, " ", fn {k, v} -> "#{k}=#{v}" end)
    assign(socket, :logs, ["[Agens] #{event} #{pairs}" | logs])
  end
end
