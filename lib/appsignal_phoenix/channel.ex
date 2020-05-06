defmodule Appsignal.Phoenix.Channel do
  @moduledoc """
  Instruments Phoenix channels.

  ## Usage

  To instrument a Phoenix channel, wrap the contents of your handle_in/3
  function in an `Appsignal.Phoenix.Channel.instrument/5` call:

      defmodule AppsignalPhoenixExampleWeb.RoomChannel do
        use Phoenix.Channel

        def join("room:lobby", _message, socket) do
          {:ok, socket}
        end

        def join("room:" <> _private_room_id, _params, _socket) do
          {:error, %{reason: "unauthorized"}}
        end

        def handle_in("new_msg", %{"body" => body} = params, socket) do
          Appsignal.Phoenix.Channel.instrument(__MODULE__, "new_msg", params, socket, fn ->
            broadcast!(socket, "new_msg", %{body: body})
            {:noreply, socket}
          end)
        end
      end

  """

  @tracer Application.get_env(:appsignal, :appsignal_tracer, Appsignal.Tracer)
  @span Application.get_env(:appsignal, :appsignal_span, Appsignal.Span)

  def instrument(module, name, socket, fun) do
    instrument(module, name, %{}, socket, fun)
  end

  def instrument(module, name, params, socket, fun) do
    Appsignal.instrument(
      "#{Appsignal.Utils.module_name(module)}##{name}",
      fn span ->
        try do
          fun.()
        catch
          kind, reason ->
            stack = __STACKTRACE__

            span
            |> @span.set_sample_data("params", params)
            |> Appsignal.Phoenix.Channel.set_sample_data(socket)
            |> @span.add_error(kind, reason, stack)
            |> @tracer.close_span()

            @tracer.ignore()
            :erlang.raise(kind, reason, stack)
        else
          result ->
            span
            |> @span.set_sample_data("params", params)
            |> Appsignal.Phoenix.Channel.set_sample_data(socket)

            result
        end
      end
    )
  end

  @doc false
  def set_sample_data(span, %Phoenix.Socket{
        id: id,
        channel: channel,
        endpoint: endpoint,
        handler: handler,
        ref: ref,
        topic: topic,
        transport: transport
      }) do
    @span.set_sample_data(span, "environment", %{
      "channel" => channel,
      "endpoint" => endpoint,
      "handler" => handler,
      "id" => id,
      "ref" => ref,
      "topic" => topic,
      "transport" => transport
    })
  end
end
