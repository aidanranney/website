defmodule PortfolioWeb.AdminMovieNightLive do
  use PortfolioWeb, :live_view

  alias Portfolio.MovieNights
  alias Portfolio.MovieNights.MovieNight

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket), do: MovieNights.subscribe_all()

    {:ok,
     socket
     |> assign(:nights, MovieNights.list_movie_nights())
     |> prepare(params)}
  end

  @impl Phoenix.LiveView
  def handle_info({:movie_nights_changed}, socket) do
    {:noreply, assign(socket, :nights, MovieNights.list_movie_nights())}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"movie_night" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(MovieNight.changeset(socket.assigns.night, params)))}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"movie_night" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.live_action do
        :edit -> MovieNights.update_movie_night(scope, socket.assigns.night, params)
        :new -> MovieNights.create_movie_night(scope, params)
      end

    case result do
      {:ok, _night} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Movie night saved."))
         |> assign(:nights, MovieNights.list_movie_nights())
         |> assign(:form, to_form(MovieNight.changeset(%MovieNight{}, %{})))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Only an admin can do that."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save that movie night."))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("lock", _params, socket) do
    case selected_night(socket) do
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Select a movie night first."))}

      {:ok, night} ->
        case MovieNights.lock_nominations(socket.assigns.current_scope, night) do
          {:ok, night} ->
            {:noreply, refresh_night(socket, night, gettext("Nominations locked."))}

          {:error, :invalid_phase} ->
            {:noreply, put_flash(socket, :error, gettext("Nominations are already locked."))}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Only an admin can do that."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not lock nominations."))}
        end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("close", _params, socket) do
    case selected_night(socket) do
      :error ->
        {:noreply, put_flash(socket, :error, "Select a movie night first.")}

      {:ok, night} ->
        case MovieNights.close_voting(socket.assigns.current_scope, night) do
          {:ok, night} ->
            {:noreply, refresh_night(socket, night, gettext("Voting closed."))}

          {:error, :invalid_phase} ->
            {:noreply, put_flash(socket, :error, gettext("Voting is not open."))}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Only an admin can do that."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not close voting."))}
        end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", _params, socket) do
    case selected_night(socket) do
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Select a movie night first."))}

      {:ok, night} ->
        case MovieNights.delete_movie_night(socket.assigns.current_scope, night) do
          {:ok, _night} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Movie night deleted."))
             |> assign(:nights, MovieNights.list_movie_nights())
             |> assign(:night, %MovieNight{})
             |> assign(:form, to_form(MovieNight.changeset(%MovieNight{}, %{})))}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Only an admin can do that."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete that movie night."))}
        end
    end
  end

  defp selected_night(%{assigns: %{night: %MovieNight{id: id}}} = socket) when not is_nil(id),
    do: {:ok, socket.assigns.night}

  defp selected_night(_socket), do: :error

  defp prepare(%{assigns: %{live_action: :edit}} = socket, %{"id" => id}) do
    night =
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> MovieNights.get_movie_night(uuid)
        :error -> nil
      end

    case night do
      nil ->
        socket
        |> assign(:night, %MovieNight{})
        |> assign(:form, to_form(MovieNight.changeset(%MovieNight{}, %{})))
        |> put_flash(:error, gettext("That movie night no longer exists."))
        |> push_navigate(to: ~p"/admin/movie-nights")

      night ->
        assign(socket, night: night, form: to_form(MovieNight.changeset(night, %{})))
    end
  end

  defp prepare(socket, _params) do
    assign(socket, night: %MovieNight{}, form: to_form(MovieNight.changeset(%MovieNight{}, %{})))
  end

  defp refresh_night(socket, night, message) do
    socket
    |> put_flash(:info, message)
    |> assign(:night, night)
    |> assign(:nights, MovieNights.list_movie_nights())
    |> assign(:form, to_form(MovieNight.changeset(night, %{})))
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.header>
        {gettext("Movie nights")}
        <:subtitle>{gettext("Schedule a night, lock nominations, and close voting.")}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/admin/movie-nights/new"}
            class="text-sm font-medium text-zinc-900 underline transition hover:text-zinc-600"
          >
            {gettext("New night")}
          </.link>
        </:actions>
      </.header>

      <section
        :if={@live_action in [:new, :edit]}
        class="rounded-lg border border-zinc-200 bg-white p-5"
      >
        <h2 class="text-sm font-semibold text-zinc-900">
          {if @live_action == :edit, do: gettext("Edit night"), else: gettext("New night")}
        </h2>

        <.form for={@form} id="movie-night-form" phx-change="validate" phx-submit="save" class="mt-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <.input field={@form[:starts_at]} type="datetime-local" label="Starts at" />
            <.input
              field={@form[:note]}
              type="text"
              label={gettext("Note (optional)")}
              placeholder={gettext("Sci-fi night")}
            />
          </div>
          <.button class="mt-2">{gettext("Save night")}</.button>
        </.form>

        <div
          :if={@live_action == :edit && @night.id}
          class="mt-5 flex flex-wrap gap-3 border-t border-zinc-200 pt-4"
        >
          <button
            :if={@night.phase == "nominating"}
            id="lock-nominations"
            type="button"
            phx-click="lock"
            data-confirm={gettext("Lock nominations? Friends will no longer be able to add films.")}
            class="rounded-md border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-zinc-900"
          >
            {gettext("Lock nominations")}
          </button>
          <button
            :if={@night.phase == "voting"}
            id="close-voting"
            type="button"
            phx-click="close"
            data-confirm={gettext("Close voting? This ends the night.")}
            class="rounded-md border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-zinc-900"
          >
            {gettext("Close voting")}
          </button>
          <button
            id="delete-night"
            type="button"
            phx-click="delete"
            data-confirm={gettext("Delete this movie night and all of its nominations and votes?")}
            class="rounded-md border border-red-200 px-3 py-1.5 text-xs font-medium text-red-700 transition hover:border-red-600"
          >
            {gettext("Delete night")}
          </button>
        </div>
      </section>

      <section id="admin-nights" class="mt-8">
        <h2 class="text-xs font-semibold uppercase tracking-widest text-zinc-500">All nights</h2>
        <div class="mt-3 grid gap-3">
          <div
            :for={night <- @nights}
            id={"night-row-#{night.id}"}
            class="flex items-center justify-between gap-4 rounded-lg border border-zinc-200 bg-white p-4"
          >
            <div>
              <p class="font-medium text-zinc-900">
                {Calendar.strftime(night.starts_at, "%b %-d, %Y · %H:%M")}
              </p>
              <p :if={night.note} class="mt-1 text-sm text-zinc-600">{night.note}</p>
            </div>
            <div class="flex items-center gap-3">
              <.phase_badge phase={night.phase} />
              <.link
                navigate={~p"/admin/movie-nights/#{night.id}/edit"}
                class="text-xs font-medium text-zinc-600 underline transition hover:text-zinc-900"
              >
                {gettext("Edit")}
              </.link>
            </div>
          </div>
          <p :if={@nights == []} class="text-sm text-zinc-500">{gettext("No movie nights yet.")}</p>
        </div>
      </section>

      <.link
        navigate={~p"/movie-night"}
        class="mt-8 inline-block text-sm text-zinc-500 underline transition hover:text-zinc-900"
      >
        {gettext("View the friend page")}
      </.link>
    </Layouts.app>
    """
  end
end
