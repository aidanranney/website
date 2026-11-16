defmodule Portfolio.MovieNightsFixtures do
  @moduledoc """
  Test helpers for movie nights.
  """

  alias Portfolio.Accounts.Scope
  alias Portfolio.AccountsFixtures
  alias Portfolio.MovieNights

  def admin_scope, do: Scope.for_user(AccountsFixtures.admin_user_fixture())

  def movie_night_fixture(attrs \\ %{}) do
    {:ok, night} =
      MovieNights.create_movie_night(
        admin_scope(),
        Enum.into(attrs, %{starts_at: ~N[2026-11-21 19:00:00]})
      )

    night
  end

  def finished_night_fixture(attrs \\ %{}) do
    night = movie_night_fixture(attrs)
    {:ok, night} = MovieNights.lock_nominations(admin_scope(), night)
    {:ok, night} = MovieNights.close_voting(admin_scope(), night)
    night
  end

  def candidate_fixture(night, tmdb_id \\ 550, scope \\ admin_scope()) do
    {:ok, candidate} = MovieNights.nominate(scope, night, tmdb_id)
    candidate
  end

  @doc """
  A locked night with `count` candidates, tmdb ids from 550 up, in nomination order.
  """
  def voting_night_with_candidates(count \\ 3) do
    night = movie_night_fixture()

    for i <- 1..count//1 do
      candidate_fixture(night, 549 + i)
    end

    {:ok, night} = MovieNights.lock_nominations(admin_scope(), night)
    {night, MovieNights.list_candidates(night)}
  end
end
