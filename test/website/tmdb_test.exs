defmodule Portfolio.TMDBTest do
  use ExUnit.Case, async: false

  alias Portfolio.TMDB

  setup do
    :persistent_term.erase({Portfolio.TMDB, :image_base})
    :ok
  end

  test "configured? reflects the token" do
    assert TMDB.configured?()
  end

  test "search normalizes results" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      assert conn.request_path == "/3/search/movie"
      assert conn.query_string =~ "query=fight"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => 550,
            "title" => "Fight Club",
            "release_date" => "1999-10-15",
            "overview" => "...",
            "poster_path" => "/poster.jpg"
          },
          %{"id" => 551, "title" => "No Date"}
        ]
      })
    end)

    assert {:ok, [fight_club, no_date]} = TMDB.search("fight")
    assert fight_club.tmdb_id == 550
    assert fight_club.title == "Fight Club"
    assert fight_club.year == 1999
    assert fight_club.overview == "..."
    assert fight_club.poster_path == "/poster.jpg"
    assert no_date.tmdb_id == 551
    assert no_date.title == "No Date"
    assert no_date.year == nil
  end

  test "get_movie normalizes a movie" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      assert conn.request_path == "/3/movie/550"

      Req.Test.json(conn, %{
        "id" => 550,
        "title" => "Fight Club",
        "release_date" => "1999-10-15",
        "overview" => "...",
        "poster_path" => "/poster.jpg"
      })
    end)

    assert {:ok, movie} = TMDB.get_movie(550)
    assert movie.tmdb_id == 550
    assert movie.title == "Fight Club"
    assert movie.year == 1999
  end

  test "404 becomes :not_found, 429 becomes {:http, 429}" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      status = if conn.request_path == "/3/movie/404", do: 404, else: 429
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
    end)

    assert {:error, :not_found} = TMDB.get_movie(404)
    assert {:error, {:http, 429}} = TMDB.get_movie(550)
    assert {:error, {:http, 429}} = TMDB.search("fight")
  end

  test "a transport error returns a tagged error instead of crashing" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, %Req.TransportError{}} = TMDB.search("fight")
  end

  test "unconfigured returns :not_configured" do
    config = Application.get_env(:website, Portfolio.TMDB)
    on_exit(fn -> Application.put_env(:website, Portfolio.TMDB, config) end)
    Application.put_env(:website, Portfolio.TMDB, Keyword.put(config, :token, nil))

    refute TMDB.configured?()
    assert {:error, :not_configured} = TMDB.search("fight")
    assert {:error, :not_configured} = TMDB.get_movie(550)
  end

  test "poster_url is nil for nil, and absolute for a path when the configuration call is stubbed" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      assert conn.request_path == "/3/configuration"
      Req.Test.json(conn, %{"images" => %{"secure_base_url" => "https://image.tmdb.test/t/p/"}})
    end)

    assert TMDB.poster_url(nil) == nil
    assert TMDB.poster_url("/poster.jpg") == "https://image.tmdb.test/t/p/w342/poster.jpg"
  end

  test "poster_url falls back when the configuration call fails" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert TMDB.poster_url("/poster.jpg") == "https://image.tmdb.org/t/p/w342/poster.jpg"
  end
end
