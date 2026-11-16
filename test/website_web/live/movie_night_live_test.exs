defmodule PortfolioWeb.MovieNightLiveTest do
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolio.AccountsFixtures
  import Portfolio.MovieNightsFixtures

  alias Portfolio.Accounts.Scope
  alias Portfolio.MovieNights

  setup do
    # Stubs must be reachable from the LiveView process and its Task.async_stream
    # children, so share them for the duration of each test.
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    stub_tmdb()
    :ok
  end

  defp stub_tmdb do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      cond do
        conn.request_path == "/3/configuration" ->
          Req.Test.json(conn, %{
            "images" => %{"secure_base_url" => "https://image.tmdb.test/t/p/"}
          })

        conn.request_path == "/3/search/movie" ->
          page =
            conn.query_string
            |> URI.decode_query()
            |> Map.get("page", "1")
            |> String.to_integer()

          id = 549 + page

          Req.Test.json(conn, %{
            "page" => page,
            "total_pages" => 2,
            "results" => [
              %{
                "id" => id,
                "title" => "Film #{id}",
                "release_date" => "1999-10-15",
                "overview" => "A film.",
                "poster_path" => nil
              }
            ]
          })

        String.starts_with?(conn.request_path, "/3/movie/") ->
          tmdb_id = conn.request_path |> String.split("/") |> List.last() |> String.to_integer()

          Req.Test.json(conn, %{
            "id" => tmdb_id,
            "title" => "Film #{tmdb_id}",
            "release_date" => "1999-10-15",
            "overview" => "A film.",
            "poster_path" => nil
          })

        true ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  test "logged-out visitors are redirected to log in", %{conn: conn} do
    night = movie_night_fixture()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/movie-night")

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/movie-night/#{night.id}")
  end

  test "an unknown or malformed night id redirects back to the index", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:live_redirect, %{to: "/movie-night"}}} =
             live(conn, ~p"/movie-night/not-a-uuid")

    assert {:error, {:live_redirect, %{to: "/movie-night"}}} =
             live(conn, ~p"/movie-night/#{Ecto.UUID.generate()}")
  end

  test "index splits upcoming and past nights", %{conn: conn} do
    past = finished_night_fixture(%{starts_at: ~N[2026-10-24 19:00:00]})
    upcoming = movie_night_fixture(%{starts_at: ~N[2026-11-21 19:00:00]})

    {:ok, lv, html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night")

    assert has_element?(lv, "#upcoming-nights #night-#{upcoming.id}")
    assert has_element?(lv, "#past-nights #night-#{past.id}")
    assert html =~ "not endorsed or certified by TMDB"
  end

  test "a friend nominates from TMDB search", %{conn: conn} do
    night = movie_night_fixture()
    {:ok, lv, _html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    lv |> form("#search-form", %{"search" => %{"query" => "fight"}}) |> render_change()
    assert has_element?(lv, "#nominate-550")

    lv |> element("#nominate-550") |> render_click()
    assert has_element?(lv, "[data-tmdb-id='550']")
    assert render(lv) =~ "Film 550"
  end

  test "infinite scroll appends the next page of TMDB results", %{conn: conn} do
    night = movie_night_fixture()
    {:ok, lv, _html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    lv |> form("#search-form", %{"search" => %{"query" => "fight"}}) |> render_change()
    assert has_element?(lv, "#nominate-550")
    assert has_element?(lv, "#results-sentinel")

    render_hook(lv, "load-more", %{})

    assert has_element?(lv, "#nominate-550")
    assert has_element?(lv, "#nominate-551")
    refute has_element?(lv, "#results-sentinel")
  end

  test "only the nominator sees a withdraw button", %{conn: conn} do
    night = movie_night_fixture()
    author = Scope.for_user(user_fixture())
    candidate = candidate_fixture(night, 550, author)

    {:ok, author_lv, _html} = live(conn |> log_in_user(author.user), ~p"/movie-night/#{night.id}")
    assert has_element?(author_lv, "#withdraw-#{candidate.id}")

    {:ok, other_lv, _html} =
      live(build_conn() |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    assert has_element?(other_lv, "[data-tmdb-id='550']")
    refute has_element?(other_lv, "#withdraw-#{candidate.id}")
  end

  test "voting page shows counts and enforces the cap", %{conn: conn} do
    {night, [a, b, c, d]} = voting_night_with_candidates(4)
    {:ok, lv, _html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    for candidate <- [a, b, c] do
      lv |> element("#vote-#{candidate.id}") |> render_click()
    end

    lv |> element("#vote-#{d.id}") |> render_click()

    assert render(lv) =~ "three votes"
    assert has_element?(lv, "#votes-used", "3 of 3")
  end

  test "a vote in one session updates another open session", %{conn: conn} do
    {night, [a | _]} = voting_night_with_candidates(2)

    {:ok, lv1, _html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    {:ok, lv2, _html} =
      live(build_conn() |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    lv1 |> element("#vote-#{a.id}") |> render_click()

    eventually(lv2, "#votes-#{a.id}", "1 vote")
  end

  test "TMDB failures render a fallback card instead of crashing", %{conn: conn} do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    {night, _} = voting_night_with_candidates(2)
    {:ok, _lv, html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    assert html =~ "Film #550"
    assert html =~ "Film #551"
  end

  test "done nights show the winner and TMDB attribution", %{conn: conn} do
    {night, [a | _]} = voting_night_with_candidates(2)
    MovieNights.toggle_vote(Scope.for_user(user_fixture()), night, a.id)
    {:ok, night} = MovieNights.close_voting(admin_scope(), night)

    {:ok, lv, html} = live(conn |> log_in_user(user_fixture()), ~p"/movie-night/#{night.id}")

    assert has_element?(lv, "#winner", "Film 550")
    assert html =~ "not endorsed or certified by TMDB"
  end

  defp eventually(lv, selector, text, tries \\ 40) do
    result =
      Enum.reduce_while(1..tries, :not_yet, fn _, _ ->
        _ = render(lv)

        if has_element?(lv, selector, text),
          do: {:halt, :ok},
          else: {:cont, :not_yet}
      end)

    assert result == :ok, "expected #{selector} to contain #{inspect(text)}"
  end
end
