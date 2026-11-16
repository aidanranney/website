defmodule PortfolioWeb.MovieNightLive.Index do
  use PortfolioWeb, :live_view

  alias Portfolio.MovieNights

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: MovieNights.subscribe_all()
    {:ok, load_nights(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:movie_nights_changed}, socket), do: {:noreply, load_nights(socket)}

  defp load_nights(socket) do
    {upcoming, past} =
      socket.assigns.current_scope
      |> MovieNights.list_movie_nights()
      |> Enum.split_with(&(&1.phase != "done"))

    assign(socket, upcoming: upcoming, past: past)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.header>
        Movie night
        <:subtitle>Nominate films, then vote for what we watch.</:subtitle>
      </.header>

      <section id="upcoming-nights" class="mt-8">
        <h2 class="text-xs font-semibold uppercase tracking-widest text-zinc-500">Upcoming</h2>
        <div class="mt-3 grid gap-3 sm:grid-cols-2">
          <.link
            :for={night <- @upcoming}
            id={"night-#{night.id}"}
            navigate={~p"/movie-night/#{night}"}
            class="group rounded-lg border border-zinc-200 bg-white p-4 transition duration-200 hover:border-zinc-900 hover:shadow-sm"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="font-medium text-zinc-900">{format_date(night.starts_at)}</p>
                <p :if={night.note} class="mt-1 text-sm text-zinc-600">{night.note}</p>
                <p class="mt-2 text-xs text-zinc-500">{length(night.candidates)} films nominated</p>
              </div>
              <.phase_badge phase={night.phase} />
            </div>
          </.link>
          <p :if={@upcoming == []} class="text-sm text-zinc-500">No movie nights coming up yet.</p>
        </div>
      </section>

      <section id="past-nights" class="mt-10">
        <h2 class="text-xs font-semibold uppercase tracking-widest text-zinc-500">Past</h2>
        <div class="mt-3 grid gap-3 sm:grid-cols-2">
          <.link
            :for={night <- @past}
            id={"night-#{night.id}"}
            navigate={~p"/movie-night/#{night}"}
            class="group rounded-lg border border-zinc-200 bg-white p-4 transition duration-200 hover:border-zinc-900 hover:shadow-sm"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="font-medium text-zinc-900">{format_date(night.starts_at)}</p>
                <p :if={night.note} class="mt-1 text-sm text-zinc-600">{night.note}</p>
                <p class="mt-2 text-xs text-zinc-500">{length(night.candidates)} films nominated</p>
              </div>
              <.phase_badge phase={night.phase} />
            </div>
          </.link>
          <p :if={@past == []} class="text-sm text-zinc-500">No past movie nights yet.</p>
        </div>
      </section>

      <.tmdb_attribution />
    </Layouts.app>
    """
  end

  defp format_date(naive), do: Calendar.strftime(naive, "%b %-d, %Y · %H:%M")
end
