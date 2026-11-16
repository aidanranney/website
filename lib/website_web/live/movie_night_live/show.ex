defmodule PortfolioWeb.MovieNightLive.Show do
  use PortfolioWeb, :live_view

  alias Portfolio.MovieNights
  alias Portfolio.TMDB

  @vote_limit_flash "You only get three votes, one per film."

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    night =
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> MovieNights.get_movie_night(scope, uuid)
        :error -> nil
      end

    case night do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That movie night no longer exists.")
         |> push_navigate(to: ~p"/movie-night")}

      night ->
        if connected?(socket), do: MovieNights.subscribe_night(night.id)

        {:ok,
         socket
         |> assign(:night, night)
         |> assign(:form, to_form(%{"query" => ""}, as: :search))
         |> assign(search_query: "", page: 0, total_pages: 0, has_more: false)
         |> stream(:results, [])
         |> load_night()}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:movie_night_changed, id}, socket) do
    if id == socket.assigns.night.id do
      {:noreply, load_night(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      case TMDB.search(query) do
        {:ok, page} ->
          socket
          |> stream(:results, page_items(page), reset: true)
          |> assign_page(query, page)

        {:error, _} ->
          socket
          |> put_flash(:error, "Movie search is unavailable right now.")
          |> stream(:results, [], reset: true)
          |> assign_page(query, empty_page())
      end

    {:noreply, assign(socket, :form, to_form(%{"query" => query}, as: :search))}
  end

  @impl Phoenix.LiveView
  def handle_event("load-more", _params, socket) do
    if socket.assigns.has_more do
      query = socket.assigns.search_query
      next_page = socket.assigns.page + 1

      socket =
        case TMDB.search(query, next_page) do
          {:ok, page} ->
            socket
            |> stream(:results, page_items(page))
            |> assign_page(query, page)

          {:error, _} ->
            socket
            |> put_flash(:error, "Could not load more films.")
            |> assign(:has_more, false)
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("nominate", %{"tmdb-id" => value}, socket) do
    case Integer.parse(value) do
      {tmdb_id, ""} ->
        case MovieNights.nominate(socket.assigns.current_scope, socket.assigns.night, tmdb_id) do
          {:ok, _} ->
            {:noreply, socket |> load_night() |> put_flash(:info, "Nomination added.")}

          {:error, :invalid_phase} ->
            {:noreply, put_flash(socket, :error, "Nominations are locked.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :info, "That film is already nominated.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not nominate that film.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Could not nominate that film.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("withdraw", %{"id" => id}, socket) do
    case find_candidate(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That nomination no longer exists.")}

      candidate ->
        case MovieNights.withdraw_nomination(socket.assigns.current_scope, candidate) do
          {:ok, _} ->
            {:noreply, socket |> load_night() |> put_flash(:info, "Nomination withdrawn.")}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "You can only withdraw your own nomination.")}

          {:error, :invalid_phase} ->
            {:noreply, put_flash(socket, :error, "Nominations are locked.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not withdraw that nomination.")}
        end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("vote", %{"id" => id}, socket) do
    case MovieNights.toggle_vote(socket.assigns.current_scope, socket.assigns.night, id) do
      {:ok, _} ->
        {:noreply, load_night(socket)}

      {:error, :vote_limit} ->
        {:noreply, put_flash(socket, :error, @vote_limit_flash)}

      {:error, :invalid_phase} ->
        {:noreply, put_flash(socket, :error, "Voting is closed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record that vote.")}
    end
  end

  defp load_night(socket) do
    scope = socket.assigns.current_scope

    case MovieNights.get_movie_night(scope, socket.assigns.night.id) do
      nil ->
        socket
        |> put_flash(:error, "That movie night no longer exists.")
        |> push_navigate(to: ~p"/movie-night")

      night ->
        load_night(socket, scope, night)
    end
  end

  defp load_night(socket, scope, night) do
    candidates = MovieNights.list_candidates(scope, night)
    movies = fetch_movies(socket.assigns[:movies] || %{}, Enum.map(candidates, & &1.tmdb_id))
    tallies = MovieNights.tallies(scope, night)
    my_votes = MovieNights.my_vote_ids(scope, night)

    items =
      Enum.map(candidates, fn candidate ->
        %{
          id: candidate.id,
          candidate: candidate,
          movie: movies[candidate.tmdb_id],
          votes: Map.get(tallies, candidate.id, 0),
          voted?: MapSet.member?(my_votes, candidate.id),
          mine?: candidate.nominated_by_id == scope.user.id
        }
      end)

    winners =
      if night.phase == "done", do: MovieNights.winning_candidates(scope, night), else: []

    socket
    |> assign(:night, night)
    |> assign(:movies, movies)
    |> assign(:winners, winners)
    |> assign(:votes_used, MovieNights.votes_used(scope, night))
    |> stream(:candidates, items, reset: true)
  end

  defp fetch_movies(cache, tmdb_ids) do
    missing = tmdb_ids |> Enum.uniq() |> Enum.reject(&Map.has_key?(cache, &1))

    fetched =
      Task.async_stream(
        missing,
        fn tmdb_id ->
          result =
            try do
              TMDB.get_movie(tmdb_id)
            rescue
              _ -> {:error, :unavailable}
            end

          {tmdb_id, result}
        end,
        max_concurrency: 4,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn
        {:ok, {tmdb_id, {:ok, movie}}}, acc -> Map.put(acc, tmdb_id, movie)
        {:ok, {tmdb_id, _error}}, acc -> Map.put(acc, tmdb_id, nil)
        _, acc -> acc
      end)

    Map.merge(cache, fetched)
  end

  defp find_candidate(socket, id) do
    MovieNights.list_candidates(socket.assigns.current_scope, socket.assigns.night)
    |> Enum.find(&(&1.id == id))
  end

  defp movie_title(movies, candidate) do
    case movies[candidate.tmdb_id] do
      nil -> "Film ##{candidate.tmdb_id}"
      movie -> movie.title
    end
  end

  defp empty_page, do: %{movies: [], page: 0, total_pages: 0}

  defp page_items(%{movies: movies}), do: Enum.map(movies, &Map.put(&1, :id, &1.tmdb_id))

  defp assign_page(socket, query, %{movies: movies, page: page, total_pages: total_pages}) do
    assign(socket,
      search_query: query,
      page: page,
      total_pages: total_pages,
      has_more: String.trim(query) != "" and movies != [] and page < total_pages
    )
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.header>
        {Calendar.strftime(@night.starts_at, "%b %-d, %Y · %H:%M")}
        <:subtitle>
          <%= if @night.note do %>
            {@night.note}
          <% else %>
            Movie night
          <% end %>
        </:subtitle>
        <:actions><.phase_badge phase={@night.phase} /></:actions>
      </.header>

      <section
        :if={@night.phase == "done"}
        id="winner"
        class="rounded-lg border border-emerald-200 bg-emerald-50 p-5"
      >
        <h2 class="text-xs font-semibold uppercase tracking-widest text-emerald-800">Winner</h2>
        <%= if @winners == [] do %>
          <p class="mt-2 text-sm text-emerald-900">No votes were cast.</p>
        <% else %>
          <p :for={winner <- @winners} class="mt-2 text-lg font-semibold text-emerald-900">
            {movie_title(@movies, winner)}
          </p>
        <% end %>
      </section>

      <section
        :if={@night.phase == "voting"}
        id="votes-used"
        class="mt-4 text-sm font-medium text-zinc-700"
      >
        {@votes_used} of 3 votes used
      </section>

      <section :if={@night.phase == "nominating"}>
        <.form for={@form} id="search-form" phx-change="search" class="mt-4">
          <.input
            field={@form[:query]}
            id="search-input"
            type="search"
            label="Find a film"
            placeholder="Search TMDB by title..."
            phx-debounce="500"
            autocomplete="off"
          />
        </.form>

        <div id="search-results" phx-update="stream" class="mt-2 grid gap-3 sm:grid-cols-2">
          <div
            :for={{dom_id, movie} <- @streams.results}
            id={dom_id}
            class="flex items-center justify-between gap-3 rounded-lg border border-zinc-200 bg-white p-3"
          >
            <div>
              <p class="text-sm font-medium text-zinc-900">{movie.title}</p>
              <p :if={movie.year} class="text-xs text-zinc-500">{movie.year}</p>
            </div>
            <button
              id={"nominate-#{movie.tmdb_id}"}
              type="button"
              phx-click="nominate"
              phx-value-tmdb-id={movie.tmdb_id}
              class="rounded-md bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-zinc-700"
            >
              Nominate
            </button>
          </div>
        </div>

        <div
          :if={@has_more}
          id="results-sentinel"
          phx-hook="InfiniteScroll"
          class="mt-4 flex justify-center py-2 text-xs text-zinc-400"
        >
          Loading more films…
        </div>
      </section>

      <h2 class="mt-8 text-xs font-semibold uppercase tracking-widest text-zinc-500">Nominees</h2>
      <div id="candidates" phx-update="stream" class="mt-3 grid gap-4 sm:grid-cols-2">
        <article
          :for={{dom_id, item} <- @streams.candidates}
          id={dom_id}
          data-tmdb-id={item.candidate.tmdb_id}
          class="flex gap-4 rounded-lg border border-zinc-200 bg-white p-4"
        >
          <div class="w-20 shrink-0">
            <%= if item.movie && item.movie.poster_path do %>
              <img
                src={TMDB.poster_url(item.movie.poster_path)}
                alt={item.movie.title}
                class="aspect-2/3 w-full rounded object-cover"
                loading="lazy"
              />
            <% else %>
              <div class="flex aspect-2/3 w-full items-center justify-center rounded bg-zinc-100 text-center text-[10px] text-zinc-500">
                No poster
              </div>
            <% end %>
          </div>

          <div class="min-w-0 flex-1">
            <h3 class="font-semibold text-zinc-900">
              {if item.movie, do: item.movie.title, else: "Film ##{item.candidate.tmdb_id}"}
            </h3>
            <p :if={item.movie && item.movie.year} class="text-xs text-zinc-500">{item.movie.year}</p>
            <p :if={item.movie && item.movie.overview} class="mt-2 line-clamp-3 text-xs text-zinc-600">
              {item.movie.overview}
            </p>

            <%= if @night.phase == "voting" do %>
              <div class="mt-3 flex items-center gap-3">
                <button
                  id={"vote-#{item.id}"}
                  type="button"
                  phx-click="vote"
                  phx-value-id={item.id}
                  class={[
                    "rounded-md px-3 py-1.5 text-xs font-medium transition",
                    if(item.voted?,
                      do: "border border-zinc-300 text-zinc-700 hover:border-zinc-900",
                      else: "bg-zinc-900 text-white hover:bg-zinc-700"
                    )
                  ]}
                >
                  {if item.voted?, do: "Remove vote", else: "Vote"}
                </button>
                <span id={"votes-#{item.id}"} class="text-xs text-zinc-500">
                  {item.votes} {if item.votes == 1, do: "vote", else: "votes"}
                </span>
              </div>
            <% end %>

            <%= if @night.phase == "nominating" && item.mine? do %>
              <button
                id={"withdraw-#{item.id}"}
                type="button"
                phx-click="withdraw"
                phx-value-id={item.id}
                class="mt-3 text-xs text-zinc-500 underline transition hover:text-zinc-900"
              >
                Withdraw my nomination
              </button>
            <% end %>
          </div>
        </article>
        <p id="candidates-empty" class="hidden only:block mt-3 text-sm text-zinc-500">
          No films nominated yet.
        </p>
      </div>

      <.tmdb_attribution />
    </Layouts.app>
    """
  end
end
