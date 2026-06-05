# Compiles only when Phoenix LiveView is available (it is an optional dependency).
if Code.ensure_loaded?(Phoenix.LiveComponent) do
  defmodule PhxNotifications.Bell do
    @moduledoc """
    Self-contained notification bell LiveComponent: trigger, unread badge, dropdown panel,
    mark-as-read, and async action handling.

    Drop it into a layout/LiveView:

        <.live_component module={PhxNotifications.Bell} id="phx_notifications_bell" recipient={@current_user} />

    For real-time updates, also add the hook to the LiveView (a LiveComponent cannot receive
    PubSub messages directly):

        on_mount {PhxNotifications.LiveView, recipient_assign: :current_user}

    ## Customisation

    Both the trigger and each row are slots. Defaults use DaisyUI classes so it works in a
    fresh Phoenix app; provide slots to render your own markup (e.g. an avatar row).

        <.live_component module={PhxNotifications.Bell} id="bell" recipient={@current_user}>
          <:trigger :let={count}>
            <.my_icon /> <span :if={count > 0}>{count}</span>
          </:trigger>
          <:row :let={n}>
            <img src={n.meta["avatar_url"]} /> {n.body}
          </:row>
        </.live_component>
    """

    use Phoenix.LiveComponent

    alias PhxNotifications.Notification

    @default_limit 20

    attr(:id, :string, required: true)
    attr(:recipient, :any, required: true, doc: "the recipient struct (e.g. current user)")
    attr(:limit, :integer, default: @default_limit)
    slot(:trigger, doc: "custom trigger; receives the unread count via :let")
    slot(:row, doc: "custom per-notification row; receives the notification via :let")

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         open?: false,
         loaded?: false,
         notifications: [],
         unread_count: 0,
         in_flight: MapSet.new(),
         errors: %{},
         trigger: [],
         row: []
       )}
    end

    @impl true
    # Forwarded by PhxNotifications.LiveView when a broadcast arrives.
    def update(%{new_notification: notification}, socket) do
      {:ok,
       assign(socket,
         notifications: [notification | socket.assigns.notifications],
         unread_count: socket.assigns.unread_count + 1
       )}
    end

    # Result of an async action, sent back via send_update/3.
    def update(%{action_result: {id, key, result}}, socket) do
      in_flight = MapSet.delete(socket.assigns.in_flight, {id, key})

      socket =
        case result do
          {:ok, _} ->
            reload(assign(socket, in_flight: in_flight))

          {:error, reason} ->
            assign(socket,
              in_flight: in_flight,
              errors: Map.put(socket.assigns.errors, id, error_message(reason))
            )
        end

      {:ok, socket}
    end

    def update(assigns, socket) do
      socket = assign(socket, Map.put_new(assigns, :limit, @default_limit))
      {:ok, if(socket.assigns.loaded?, do: socket, else: reload(socket))}
    end

    @impl true
    def handle_event("toggle", _params, socket) do
      {:noreply, assign(socket, open?: !socket.assigns.open?)}
    end

    def handle_event("mark_all_read", _params, socket) do
      {:ok, _} = PhxNotifications.mark_all_read(socket.assigns.recipient)
      {:noreply, reload(socket)}
    end

    def handle_event("open_link", %{"id" => id, "url" => url}, socket) do
      {:noreply,
       socket
       |> mark_one_read(String.to_integer(id))
       |> push_navigate(to: url)}
    end

    def handle_event("run_action", %{"id" => id, "key" => key}, socket) do
      id = String.to_integer(id)
      notification = Enum.find(socket.assigns.notifications, &(&1.id == id))
      parent = self()
      component_id = socket.assigns.id

      Task.start(fn ->
        result = PhxNotifications.execute_action(notification, key)
        send_update(parent, __MODULE__, id: component_id, action_result: {id, key, result})
      end)

      {:noreply,
       assign(socket,
         in_flight: MapSet.put(socket.assigns.in_flight, {id, key}),
         errors: Map.delete(socket.assigns.errors, id)
       )}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div class="phx-notifications dropdown dropdown-end">
        <div phx-click="toggle" phx-target={@myself} class="phx-notifications__trigger">
          <%= if @trigger != [] do %>
            {render_slot(@trigger, @unread_count)}
          <% else %>
            <button type="button" class="btn btn-ghost btn-circle" aria-label="Notifications">
              <span class="indicator">
                <span
                  :if={@unread_count > 0}
                  class="badge badge-sm badge-primary indicator-item"
                >
                  {@unread_count}
                </span>
                <span class="text-xl" aria-hidden="true">&#128276;</span>
              </span>
            </button>
          <% end %>
        </div>

        <div
          :if={@open?}
          class="phx-notifications__panel dropdown-content card card-compact w-80 bg-base-100 shadow z-10"
        >
          <div class="card-body p-2">
            <p :if={@notifications == []} class="p-4 text-sm opacity-60">No notifications</p>
            <ul class="menu menu-sm w-full">
              <li
                :for={n <- @notifications}
                class={["phx-notifications__row", is_nil(n.read_at) && "is-unread font-medium"]}
              >
                <%= if @row != [] do %>
                  {render_slot(@row, n)}
                <% else %>
                  <.default_row
                    notification={n}
                    myself={@myself}
                    in_flight={@in_flight}
                    error={@errors[n.id]}
                  />
                <% end %>
              </li>
            </ul>
            <button
              :if={@unread_count > 0}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="mark_all_read"
              phx-target={@myself}
            >
              Mark all as read
            </button>
          </div>
        </div>
      </div>
      """
    end

    attr(:notification, :map, required: true)
    attr(:myself, :any, required: true)
    attr(:in_flight, :any, required: true)
    attr(:error, :string, default: nil)

    defp default_row(assigns) do
      assigns = assign(assigns, :type, Notification.type(assigns.notification))

      ~H"""
      <div class="phx-notifications__default-row">
        <a
          :if={@type == :link}
          href="#"
          phx-click="open_link"
          phx-value-id={@notification.id}
          phx-value-url={@notification.url}
          phx-target={@myself}
        >
          <span :if={@notification.title} class="block font-semibold">{@notification.title}</span>
          {@notification.body}
        </a>

        <div :if={@type != :link}>
          <span :if={@notification.title} class="block font-semibold">{@notification.title}</span>
          {@notification.body}
        </div>

        <div :if={@type == :action} class="mt-1 flex gap-1">
          <button
            :for={action <- @notification.actions}
            type="button"
            class="btn btn-xs btn-primary"
            phx-click="run_action"
            phx-value-id={@notification.id}
            phx-value-key={action["key"]}
            phx-target={@myself}
            phx-disable-with="…"
            disabled={MapSet.member?(@in_flight, {@notification.id, action["key"]})}
          >
            {action["label"] || action["key"]}
          </button>
        </div>

        <p :if={@error} class="text-error text-xs mt-1">{@error}</p>
      </div>
      """
    end

    defp reload(socket) do
      recipient = socket.assigns.recipient
      limit = socket.assigns[:limit] || @default_limit

      assign(socket,
        notifications: PhxNotifications.list(recipient, limit: limit),
        unread_count: PhxNotifications.unread_count(recipient),
        loaded?: true
      )
    end

    defp mark_one_read(socket, id) do
      case Enum.find(socket.assigns.notifications, &(&1.id == id)) do
        nil ->
          socket

        notification ->
          with({:ok, _} <- PhxNotifications.mark_read(notification), do: reload(socket))
      end
    end

    defp error_message(reason) when is_binary(reason), do: reason
    defp error_message(reason), do: inspect(reason)
  end
end
