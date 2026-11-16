defmodule PortfolioWeb.AdminMovieNightLiveTest do
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolio.AccountsFixtures
  import Portfolio.MovieNightsFixtures

  alias Portfolio.MovieNights
  alias Portfolio.MovieNights.Candidate
  alias Portfolio.MovieNights.MovieNight
  alias Portfolio.Repo

  defp admin_paths do
    night = movie_night_fixture()

    [
      ~p"/admin/movie-nights",
      ~p"/admin/movie-nights/new",
      ~p"/admin/movie-nights/#{night.id}/edit"
    ]
  end

  test "logged-out visitors are redirected from every admin route", %{conn: conn} do
    for path <- admin_paths() do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
    end
  end

  test "non-admins are redirected from every admin route" do
    for path <- admin_paths() do
      conn = build_conn() |> log_in_user(user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
    end
  end

  test "admin creates a night", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/movie-nights/new")

    html =
      lv
      |> form("#movie-night-form", %{
        "movie_night" => %{"starts_at" => "2026-12-05T20:30", "note" => "Sci-fi night"}
      })
      |> render_submit()

    assert html =~ "Movie night saved."
    assert html =~ "Sci-fi night"

    [night] = Repo.all(MovieNight)
    assert has_element?(lv, "#night-row-#{night.id}")
  end

  test "admin edits a night", %{conn: conn} do
    night = movie_night_fixture()
    conn = log_in_user(conn, admin_user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/movie-nights/#{night.id}/edit")

    html =
      lv
      |> form("#movie-night-form", %{
        "movie_night" => %{"starts_at" => "2026-12-05T20:30", "note" => "Changed note"}
      })
      |> render_submit()

    assert html =~ "Dec 5, 2026"
    assert html =~ "Changed note"

    assert MovieNights.get_movie_night(admin_scope(), night.id).starts_at ==
             ~N[2026-12-05 20:30:00]
  end

  test "admin locks nominations then closes voting", %{conn: conn} do
    night = movie_night_fixture()
    conn = log_in_user(conn, admin_user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/movie-nights/#{night.id}/edit")

    assert has_element?(lv, "#lock-nominations")
    lv |> element("#lock-nominations") |> render_click()
    assert MovieNights.get_movie_night(admin_scope(), night.id).phase == "voting"
    assert has_element?(lv, "#close-voting")

    lv |> element("#close-voting") |> render_click()
    assert MovieNights.get_movie_night(admin_scope(), night.id).phase == "done"
    refute has_element?(lv, "#close-voting")
  end

  test "admin deletes a night and its candidates cascade", %{conn: conn} do
    night = movie_night_fixture()
    candidate_fixture(night)
    assert Repo.aggregate(Candidate, :count) == 1

    conn = log_in_user(conn, admin_user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/movie-nights/#{night.id}/edit")

    lv |> element("#delete-night") |> render_click()

    refute has_element?(lv, "#night-row-#{night.id}")
    assert Repo.aggregate(Candidate, :count) == 0
  end

  test "an invalid night id redirects back to the admin index", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())

    assert {:error, {:live_redirect, %{to: "/admin/movie-nights"}}} =
             live(conn, ~p"/admin/movie-nights/not-a-uuid/edit")
  end
end
