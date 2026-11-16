defmodule Portfolio.MovieNightsTest do
  use Portfolio.DataCase, async: true

  import Portfolio.AccountsFixtures
  import Portfolio.MovieNightsFixtures

  alias Portfolio.Accounts.Scope
  alias Portfolio.MovieNights
  alias Portfolio.MovieNights.Candidate
  alias Portfolio.MovieNights.MovieNight

  describe "movie night admin CRUD" do
    test "creates a night for admins and rejects friends" do
      assert {:ok, %MovieNight{phase: "nominating"}} =
               MovieNights.create_movie_night(admin_scope(), %{
                 starts_at: ~N[2026-11-21 19:00:00],
                 note: "Sci-fi"
               })

      assert {:error, :unauthorized} =
               MovieNights.create_movie_night(Scope.for_user(user_fixture()), %{
                 starts_at: ~N[2026-11-21 19:00:00]
               })

      assert {:error, :unauthorized} =
               MovieNights.create_movie_night(nil, %{starts_at: ~N[2026-11-21 19:00:00]})
    end

    test "requires starts_at" do
      assert {:error, %Ecto.Changeset{}} = MovieNights.create_movie_night(admin_scope(), %{})
    end

    test "deleting a night removes its candidates and votes" do
      night = movie_night_fixture()

      candidate =
        Repo.insert!(%MovieNights.Candidate{
          movie_night_id: night.id,
          nominated_by_id: user_fixture().id,
          tmdb_id: 550
        })

      Repo.insert!(%MovieNights.Vote{candidate_id: candidate.id, user_id: user_fixture().id})

      assert Repo.aggregate(MovieNights.Candidate, :count) == 1
      assert Repo.aggregate(MovieNights.Vote, :count) == 1
      assert {:ok, _} = MovieNights.delete_movie_night(admin_scope(), night)
      assert Repo.aggregate(MovieNights.Candidate, :count) == 0
      assert Repo.aggregate(MovieNights.Vote, :count) == 0
    end

    test "lists non-done nights ascending and done nights descending" do
      later = movie_night_fixture(%{starts_at: ~N[2026-12-01 19:00:00]})
      sooner = movie_night_fixture(%{starts_at: ~N[2026-11-21 19:00:00]})
      done = finished_night_fixture(%{starts_at: ~N[2026-10-24 19:00:00]})

      assert [sooner_id, later_id, done_id] =
               Enum.map(MovieNights.list_movie_nights(), & &1.id)

      assert sooner_id == sooner.id
      assert later_id == later.id
      assert done_id == done.id
    end

    test "locks nominations only from nominating" do
      night = movie_night_fixture()

      assert {:ok, %MovieNight{phase: "voting"}} =
               MovieNights.lock_nominations(admin_scope(), night)

      assert {:error, :invalid_phase} = MovieNights.lock_nominations(admin_scope(), night)
    end

    test "closes voting only from voting" do
      night = movie_night_fixture()
      assert {:error, :invalid_phase} = MovieNights.close_voting(admin_scope(), night)
    end

    test "non-admins cannot change phase or delete" do
      night = movie_night_fixture()
      friend = Scope.for_user(user_fixture())
      assert {:error, :unauthorized} = MovieNights.lock_nominations(friend, night)
      assert {:error, :unauthorized} = MovieNights.delete_movie_night(friend, night)
    end
  end

  describe "nominations" do
    test "a friend nominates a film once, duplicate gets a changeset error" do
      night = movie_night_fixture()
      scope = Scope.for_user(user_fixture())

      assert {:ok, %Candidate{tmdb_id: 550}} = MovieNights.nominate(scope, night, 550)

      assert {:error, %Ecto.Changeset{} = cs} = MovieNights.nominate(scope, night, 550)
      assert {"has already been taken", _} = cs.errors[:movie_night_id]
    end

    test "nominating after lock is rejected" do
      night = movie_night_fixture()
      {:ok, night} = MovieNights.lock_nominations(admin_scope(), night)

      assert {:error, :invalid_phase} =
               MovieNights.nominate(Scope.for_user(user_fixture()), night, 550)
    end

    test "you can withdraw only your own nomination, only while nominating" do
      night = movie_night_fixture()
      author = Scope.for_user(user_fixture())
      other = Scope.for_user(user_fixture())
      {:ok, candidate} = MovieNights.nominate(author, night, 550)

      assert {:error, :unauthorized} = MovieNights.withdraw_nomination(other, candidate)
      assert {:ok, %Candidate{}} = MovieNights.withdraw_nomination(author, candidate)
      assert [] = MovieNights.list_candidates(night)
    end

    test "withdrawing after lock is rejected" do
      night = movie_night_fixture()
      author = Scope.for_user(user_fixture())
      {:ok, candidate} = MovieNights.nominate(author, night, 550)
      {:ok, _night} = MovieNights.lock_nominations(admin_scope(), night)

      assert {:error, :invalid_phase} = MovieNights.withdraw_nomination(author, candidate)
    end

    test "nominations are visible to every friend" do
      night = movie_night_fixture()
      author = Scope.for_user(user_fixture())

      assert {:ok, candidate} = MovieNights.nominate(author, night, 550)
      assert [%Candidate{id: id}] = MovieNights.list_candidates(night)
      assert id == candidate.id
    end

    test "anonymous callers cannot nominate or withdraw" do
      night = movie_night_fixture()
      assert {:error, :unauthorized} = MovieNights.nominate(nil, night, 550)
      assert {:error, :unauthorized} = MovieNights.nominate(%Scope{}, night, 550)

      candidate = candidate_fixture(night)
      assert {:error, :unauthorized} = MovieNights.withdraw_nomination(%Scope{}, candidate)
      assert [%Candidate{id: id}] = MovieNights.list_candidates(night)
      assert id == candidate.id
    end

    test "voting night fixture locks nominations with candidates in tmdb-id order" do
      {night, candidates} = voting_night_with_candidates()

      assert %MovieNight{phase: "voting"} = night
      assert Enum.map(candidates, & &1.tmdb_id) == [550, 551, 552]
      assert length(MovieNights.list_candidates(night)) == 3
    end

    test "voting night fixture with zero candidates" do
      assert {_, []} = voting_night_with_candidates(0)
    end

    test "candidates come back in nomination order even within one second" do
      night = movie_night_fixture()
      scope = Scope.for_user(user_fixture())

      for tmdb_id <- [550, 551, 552] do
        assert {:ok, %Candidate{}} = MovieNights.nominate(scope, night, tmdb_id)
      end

      assert Enum.map(MovieNights.list_candidates(night), & &1.tmdb_id) == [550, 551, 552]
    end

    test "withdraw authorization wins over phase" do
      night = movie_night_fixture()
      author = Scope.for_user(user_fixture())
      other = Scope.for_user(user_fixture())
      {:ok, candidate} = MovieNights.nominate(author, night, 550)
      {:ok, _night} = MovieNights.lock_nominations(admin_scope(), night)

      assert {:error, :unauthorized} = MovieNights.withdraw_nomination(other, candidate)
    end

    test "a successful nomination broadcasts, a rejected one does not" do
      night = movie_night_fixture()
      scope = Scope.for_user(user_fixture())
      MovieNights.subscribe_night(night.id)
      MovieNights.subscribe_all()

      assert {:ok, %Candidate{}} = MovieNights.nominate(scope, night, 550)
      assert_receive {:movie_night_changed, id}
      assert id == night.id
      assert_receive {:movie_nights_changed}

      # lock broadcasts too; drain those before checking the rejected nomination
      {:ok, _night} = MovieNights.lock_nominations(admin_scope(), night)
      assert_receive {:movie_night_changed, ^id}
      assert_receive {:movie_nights_changed}

      assert {:error, :invalid_phase} = MovieNights.nominate(scope, night, 551)
      refute_receive {:movie_night_changed, ^id}
      refute_receive {:movie_nights_changed}
    end
  end

  describe "voting" do
    test "toggles votes and refuses a fourth distinct film" do
      {night, [a, b, c, d]} = voting_night_with_candidates(4)
      scope = Scope.for_user(user_fixture())
      assert {:ok, :voted} = MovieNights.toggle_vote(scope, night, a.id)
      assert {:ok, :voted} = MovieNights.toggle_vote(scope, night, b.id)
      assert {:ok, :voted} = MovieNights.toggle_vote(scope, night, c.id)
      assert {:error, :vote_limit} = MovieNights.toggle_vote(scope, night, d.id)
      assert MovieNights.votes_used(scope, night) == 3
      assert {:ok, :unvoted} = MovieNights.toggle_vote(scope, night, a.id)
      assert MovieNights.votes_used(scope, night) == 2
      assert {:ok, :voted} = MovieNights.toggle_vote(scope, night, d.id)
    end

    test "rejects votes while nominating" do
      night = movie_night_fixture()
      candidate = candidate_fixture(night)

      assert {:error, :invalid_phase} =
               MovieNights.toggle_vote(Scope.for_user(user_fixture()), night, candidate.id)
    end

    test "rejects a candidate from another night" do
      other = candidate_fixture(movie_night_fixture())
      {night, _} = voting_night_with_candidates(1)

      assert {:error, :not_found} =
               MovieNights.toggle_vote(Scope.for_user(user_fixture()), night, other.id)
    end

    test "tallies and ties" do
      {night, [a, b, c | _]} = voting_night_with_candidates(3)
      u1 = Scope.for_user(user_fixture())
      u2 = Scope.for_user(user_fixture())
      u3 = Scope.for_user(user_fixture())
      MovieNights.toggle_vote(u1, night, a.id)
      MovieNights.toggle_vote(u1, night, b.id)
      MovieNights.toggle_vote(u2, night, a.id)
      MovieNights.toggle_vote(u2, night, b.id)
      MovieNights.toggle_vote(u3, night, c.id)

      assert MovieNights.tallies(night) == %{a.id => 2, b.id => 2, c.id => 1}

      assert Enum.sort(Enum.map(MovieNights.winning_candidates(night), & &1.id)) ==
               Enum.sort([a.id, b.id])
    end

    test "two rapid votes from the same user cannot exceed the cap" do
      {night, [a, b, c, d]} = voting_night_with_candidates(4)
      scope = Scope.for_user(user_fixture())
      MovieNights.toggle_vote(scope, night, a.id)
      MovieNights.toggle_vote(scope, night, b.id)
      MovieNights.toggle_vote(scope, night, c.id)

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            receive do
              :go -> MovieNights.toggle_vote(scope, night, d.id)
            end
          end)
        end

      Enum.each(tasks, &Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), &1.pid))
      Enum.each(tasks, &send(&1.pid, :go))
      Enum.each(tasks, &Task.await/1)

      assert MovieNights.votes_used(scope, night) <= 3
    end

    test "anonymous callers cannot vote" do
      {night, [a | _]} = voting_night_with_candidates(1)
      assert {:error, :unauthorized} = MovieNights.toggle_vote(nil, night, a.id)
    end

    test "rejects votes on a done night" do
      night = movie_night_fixture()
      candidate = candidate_fixture(night)
      {:ok, night} = MovieNights.lock_nominations(admin_scope(), night)
      {:ok, night} = MovieNights.close_voting(admin_scope(), night)

      assert {:error, :invalid_phase} =
               MovieNights.toggle_vote(Scope.for_user(user_fixture()), night, candidate.id)
    end

    test "winning_candidates is empty when nobody voted" do
      {night, _} = voting_night_with_candidates(2)
      assert MovieNights.winning_candidates(night) == []
    end

    test "a single winner" do
      {night, [a, _b]} = voting_night_with_candidates(2)
      scope = Scope.for_user(user_fixture())
      MovieNights.toggle_vote(scope, night, a.id)
      assert [winner] = MovieNights.winning_candidates(night)
      assert winner.id == a.id
    end

    test "my_vote_ids reflects toggling" do
      {night, [a, _b]} = voting_night_with_candidates(2)
      scope = Scope.for_user(user_fixture())
      assert MapSet.equal?(MovieNights.my_vote_ids(scope, night), MapSet.new())
      MovieNights.toggle_vote(scope, night, a.id)
      assert MovieNights.my_vote_ids(scope, night) == MapSet.new([a.id])
      MovieNights.toggle_vote(scope, night, a.id)
      assert MapSet.equal?(MovieNights.my_vote_ids(scope, night), MapSet.new())
    end

    test "tallies and votes_used are per-user and per-night" do
      {night1, [a1]} = voting_night_with_candidates(1)
      {night2, [a2]} = voting_night_with_candidates(1)
      scope1 = Scope.for_user(user_fixture())
      scope2 = Scope.for_user(user_fixture())
      MovieNights.toggle_vote(scope1, night1, a1.id)
      assert MovieNights.votes_used(scope1, night1) == 1
      assert MovieNights.votes_used(scope2, night1) == 0
      assert MovieNights.votes_used(scope1, night2) == 0
      assert MovieNights.tallies(night2) == %{}
      _ = a2
    end

    test "a successful vote broadcasts both messages and a rejected one broadcasts none" do
      night = movie_night_fixture()
      c1 = candidate_fixture(night, 550)
      c2 = candidate_fixture(night, 551)
      c3 = candidate_fixture(night, 552)
      c4 = candidate_fixture(night, 553)
      scope = Scope.for_user(user_fixture())
      {:ok, night} = MovieNights.lock_nominations(admin_scope(), night)

      MovieNights.toggle_vote(scope, night, c1.id)
      MovieNights.toggle_vote(scope, night, c2.id)
      MovieNights.toggle_vote(scope, night, c3.id)

      MovieNights.subscribe_night(night.id)
      MovieNights.subscribe_all()

      assert {:error, :vote_limit} = MovieNights.toggle_vote(scope, night, c4.id)
      refute_receive {:movie_night_changed, _}
      refute_receive {:movie_nights_changed}

      assert {:ok, :unvoted} = MovieNights.toggle_vote(scope, night, c1.id)
      assert_receive {:movie_night_changed, received_id}
      assert received_id == night.id
      assert_receive {:movie_nights_changed}

      assert {:ok, :voted} = MovieNights.toggle_vote(scope, night, c4.id)
      assert_receive {:movie_night_changed, received_id2}
      assert received_id2 == night.id
      assert_receive {:movie_nights_changed}
    end
  end
end
