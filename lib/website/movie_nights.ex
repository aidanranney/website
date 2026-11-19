defmodule Portfolio.MovieNights do
  @moduledoc """
  The MovieNights context.

  Movie nights move forward through phases only: `nominating` → `voting` → `done`.
  Admin writes broadcast on `"movie_nights"` and `"movie_nights:<id>"`.
  """

  import Ecto.Query, warn: false
  alias Portfolio.Repo

  alias Portfolio.Accounts.Scope
  alias Portfolio.MovieNights.Candidate
  alias Portfolio.MovieNights.MovieNight
  alias Portfolio.MovieNights.Vote

  @all_topic "movie_nights"

  @doc """
  Lists movie nights: upcoming, open, then finished nights.
  Finished nights are sorted in descending order.
  Candidates are preloaded.
  """
  @spec list_movie_nights() :: [MovieNight.t()]
  def list_movie_nights() do
    upcoming =
      Repo.all(
        from(n in MovieNight,
          where: n.phase != "done",
          order_by: [asc: n.starts_at],
          preload: [:candidates]
        )
      )

    done =
      Repo.all(
        from(n in MovieNight,
          where: n.phase == "done",
          order_by: [desc: n.starts_at],
          preload: [:candidates]
        )
      )

    upcoming ++ done
  end

  @doc """
  Gets a single movie night. Returns nil if no record found.
  """
  @spec get_movie_night(binary()) :: MovieNight.t() | nil
  def get_movie_night(id), do: Repo.get(MovieNight, id)

  @doc """
  Creates a movie night. Admins only.
  """
  @spec create_movie_night(Scope.t(), map()) ::
          {:ok, MovieNight.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def create_movie_night(scope, attrs) do
    if admin?(scope) do
      %MovieNight{}
      |> MovieNight.changeset(attrs)
      |> Repo.insert()
      |> broadcast()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Updates a movie night's schedule and note. Admins only.
  """
  @spec update_movie_night(Scope.t(), MovieNight.t(), map()) ::
          {:ok, MovieNight.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update_movie_night(scope, %MovieNight{} = night, attrs) do
    if admin?(scope) do
      night
      |> MovieNight.changeset(attrs)
      |> Repo.update()
      |> broadcast()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a movie night, its candidates and votes. Admins only.
  """
  @spec delete_movie_night(Scope.t(), MovieNight.t()) ::
          {:ok, MovieNight.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def delete_movie_night(scope, %MovieNight{} = night) do
    if admin?(scope) do
      night
      |> Repo.delete()
      |> broadcast()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Locks nominations, moving a night from `nominating` to `voting`. Admins only.
  """
  @spec lock_nominations(Scope.t(), MovieNight.t()) ::
          {:ok, MovieNight.t()} | {:error, Ecto.Changeset.t() | :invalid_phase | :unauthorized}
  def lock_nominations(scope, %MovieNight{} = night) do
    transition(scope, night, "nominating", "voting")
  end

  @doc """
  Closes voting, moving a night from `voting` to `done`. Admins only.
  """
  @spec close_voting(Scope.t(), MovieNight.t()) ::
          {:ok, MovieNight.t()} | {:error, Ecto.Changeset.t() | :invalid_phase | :unauthorized}
  def close_voting(scope, %MovieNight{} = night) do
    transition(scope, night, "voting", "done")
  end

  defp transition(scope, %MovieNight{id: id}, expected, next) do
    if admin?(scope) do
      transact(id, &advance_phase(&1, expected, next))
    else
      {:error, :unauthorized}
    end
  end

  defp advance_phase(%MovieNight{phase: expected} = night, expected, next) do
    night
    |> Ecto.Changeset.change(phase: next)
    |> Repo.update()
  end

  defp advance_phase(_night, _expected, _next), do: {:error, :invalid_phase}

  @doc """
  Lists a night's candidates in the order they were nominated.
  """
  @spec list_candidates(MovieNight.t()) :: [Candidate.t()]
  def list_candidates(%MovieNight{id: id}) do
    Repo.all(
      from(c in Candidate,
        where: c.movie_night_id == ^id,
        order_by: [asc: c.inserted_at]
      )
    )
  end

  @doc """
  Nominates a film for a night while it is `nominating`.
  """
  @spec nominate(Scope.t(), MovieNight.t(), binary()) ::
          {:ok, Candidate.t()} | {:error, Ecto.Changeset.t() | :invalid_phase | :unauthorized}
  def nominate(nil, %MovieNight{}, _tmdb_id), do: {:error, :unauthorized}

  def nominate(%Scope{user: nil}, %MovieNight{}, _tmdb_id), do: {:error, :unauthorized}

  def nominate(%Scope{user: user}, %MovieNight{id: id}, tmdb_id) do
    transact(id, fn night ->
      if night.phase == "nominating" do
        %Candidate{movie_night_id: night.id, nominated_by_id: user.id}
        |> Candidate.changeset(%{tmdb_id: tmdb_id})
        |> Repo.insert()
      else
        {:error, :invalid_phase}
      end
    end)
  end

  @doc """
  Withdraws a nomination. Only its author can withdraw, only while `nominating`.
  """
  @spec withdraw_nomination(Scope.t(), Candidate.t()) ::
          {:ok, Candidate.t()} | {:error, Ecto.Changeset.t() | :invalid_phase | :unauthorized}
  def withdraw_nomination(nil, %Candidate{}), do: {:error, :unauthorized}

  def withdraw_nomination(%Scope{user: nil}, %Candidate{}), do: {:error, :unauthorized}

  def withdraw_nomination(%Scope{user: user}, %Candidate{} = candidate) do
    transact(candidate.movie_night_id, fn night ->
      cond do
        candidate.nominated_by_id != user.id -> {:error, :unauthorized}
        night.phase != "nominating" -> {:error, :invalid_phase}
        true -> Repo.delete(candidate)
      end
    end)
  end

  ## Voting

  @max_votes 3
  @doc """
  Toggles a user's vote on a candidate while the night is `voting`.
  A user may vote for at most #{@max_votes} distinct candidates per night.
  """
  @spec toggle_vote(Scope.t() | nil, MovieNight.t(), binary()) ::
          {:ok, :voted | :unvoted}
          | {:error,
             :unauthorized | :invalid_phase | :not_found | :vote_limit | Ecto.Changeset.t()}
  def toggle_vote(%Scope{user: %{id: user_id}}, %MovieNight{id: id}, candidate_id) do
    id
    |> transact(&toggle_in_night(&1, candidate_id, user_id))
    |> notify_vote_change(id)
  end

  def toggle_vote(_scope, _night, _candidate_id), do: {:error, :unauthorized}

  defp toggle_in_night(night, candidate_id, user_id) do
    with :ok <- ensure_phase(night, "voting"),
         {:ok, candidate} <- fetch_candidate(night, candidate_id) do
      flip_vote(candidate, user_id)
    end
  end

  defp flip_vote(candidate, user_id) do
    case Repo.get_by(Vote, candidate_id: candidate.id, user_id: user_id) do
      nil -> cast_vote(candidate, user_id)
      vote -> remove_vote(vote)
    end
  end

  defp cast_vote(candidate, user_id) do
    with :ok <- ensure_under_limit(candidate.movie_night_id, user_id),
         {:ok, _vote} <- insert_vote(candidate, user_id) do
      {:ok, :voted}
    end
  end

  defp insert_vote(candidate, user_id) do
    %Vote{candidate_id: candidate.id, user_id: user_id}
    |> Vote.changeset(%{})
    |> Repo.insert(on_conflict: :nothing)
  end

  defp remove_vote(vote) do
    with {:ok, _vote} <- Repo.delete(vote), do: {:ok, :unvoted}
  end

  defp ensure_under_limit(night_id, user_id) do
    if count_votes(night_id, user_id) < @max_votes, do: :ok, else: {:error, :vote_limit}
  end

  defp notify_vote_change({:ok, _} = ok, night_id) do
    broadcast_night(night_id)
    ok
  end

  defp notify_vote_change(error, _night_id), do: error

  defp ensure_phase(%MovieNight{phase: phase}, phase), do: :ok
  defp ensure_phase(_night, _phase), do: {:error, :invalid_phase}

  defp fetch_candidate(%MovieNight{id: id}, candidate_id) do
    case Repo.get_by(Candidate, id: candidate_id, movie_night_id: id) do
      nil -> {:error, :not_found}
      candidate -> {:ok, candidate}
    end
  end

  defp count_votes(night_id, user_id) do
    Repo.aggregate(
      from(v in Vote,
        join: c in Candidate,
        on: v.candidate_id == c.id,
        where: c.movie_night_id == ^night_id and v.user_id == ^user_id
      ),
      :count
    )
  end

  @doc """
  Returns a map of vote counts for the night.
  """
  @spec tallies(MovieNight.t()) :: %{binary() => integer()}
  def tallies(%MovieNight{id: id}) do
    Repo.all(
      from(v in Vote,
        join: c in Candidate,
        on: v.candidate_id == c.id,
        where: c.movie_night_id == ^id,
        group_by: v.candidate_id,
        select: {v.candidate_id, count(v.id)}
      )
    )
    |> Map.new()
  end

  @doc "Counts the scope user's votes for the night."
  def votes_used(nil, _night), do: 0

  def votes_used(%Scope{user: nil}, _night), do: 0

  def votes_used(%Scope{user: %{id: user_id}}, %MovieNight{id: id}) do
    Repo.aggregate(
      from(v in Vote,
        join: c in Candidate,
        on: v.candidate_id == c.id,
        where: c.movie_night_id == ^id and v.user_id == ^user_id
      ),
      :count
    )
  end

  @doc "Returns a MapSet of the scope user's voted candidate ids for the night."
  def my_vote_ids(nil, _night), do: MapSet.new()

  def my_vote_ids(%Scope{user: nil}, _night), do: MapSet.new()

  def my_vote_ids(%Scope{user: %{id: user_id}}, %MovieNight{id: id}) do
    Repo.all(
      from(v in Vote,
        join: c in Candidate,
        on: v.candidate_id == c.id,
        where: c.movie_night_id == ^id and v.user_id == ^user_id,
        select: v.candidate_id
      )
    )
    |> MapSet.new()
  end

  @doc "Returns all candidates tied for the highest vote count (or [] when no votes)."
  def winning_candidates(%MovieNight{} = night) do
    t = tallies(night)

    if map_size(t) == 0 do
      []
    else
      max_count = t |> Map.values() |> Enum.max()

      winner_ids =
        t
        |> Enum.filter(fn {_id, count} -> count == max_count end)
        |> Enum.map(fn {id, _} -> id end)

      Repo.all(
        from(c in Candidate,
          where: c.id in ^winner_ids,
          order_by: [asc: c.inserted_at]
        )
      )
    end
  end

  defp transact(id, fun) do
    # SQLite has no row locks; IMMEDIATE serializes writers from BEGIN.
    Repo.transact(fn -> fun.(load_night(id)) end, mode: :immediate)
    |> broadcast()
  end

  defp load_night(id) do
    Repo.one!(from(n in MovieNight, where: n.id == ^id))
  end

  ## PubSub

  @doc "Subscribes to changes across all movie nights."
  def subscribe_all, do: Phoenix.PubSub.subscribe(Portfolio.PubSub, @all_topic)

  @doc "Subscribes to changes for a single movie night."
  def subscribe_night(id), do: Phoenix.PubSub.subscribe(Portfolio.PubSub, night_topic(id))

  defp night_topic(id), do: "movie_nights:#{id}"

  defp broadcast({:ok, %MovieNight{id: id}} = result) do
    broadcast_night(id)
    result
  end

  defp broadcast({:ok, %Candidate{movie_night_id: id}} = result) do
    broadcast_night(id)
    result
  end

  defp broadcast(error), do: error

  defp broadcast_night(id) do
    Phoenix.PubSub.broadcast(Portfolio.PubSub, @all_topic, {:movie_nights_changed})
    Phoenix.PubSub.broadcast(Portfolio.PubSub, night_topic(id), {:movie_night_changed, id})
  end

  defp admin?(scope), do: Scope.admin?(scope)
end
