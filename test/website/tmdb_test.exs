defmodule Portfolio.TMDBTest do
  use ExUnit.Case, async: false

  alias Portfolio.TMDB

  test "configured? reflects the token" do
    assert TMDB.configured?()
  end

  test "search normalizes results and exposes paging" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      assert conn.request_path == "/3/search/movie"
      assert conn.query_string =~ "query=fight"
      assert conn.query_string =~ "page=1"

      Req.Test.json(conn, %{
        "page" => 1,
        "total_pages" => 3,
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

    assert {:ok, page} = TMDB.search("fight")
    assert page.page == 1
    assert page.total_pages == 3
    [fight_club, no_date] = page.movies
    assert fight_club.tmdb_id == 550
    assert fight_club.title == "Fight Club"
    assert fight_club.year == 1999
    assert fight_club.overview == "..."
    assert fight_club.poster_path == "/poster.jpg"
    assert no_date.tmdb_id == 551
    assert no_date.title == "No Date"
    assert no_date.year == nil
  end

  test "search requests the given page and forwards paging metadata" do
    Req.Test.stub(Portfolio.TMDB, fn conn ->
      assert conn.query_string =~ "page=2"
      Req.Test.json(conn, %{"page" => 2, "total_pages" => 5, "results" => []})
    end)

    assert {:ok, %{movies: [], page: 2, total_pages: 5}} = TMDB.search("fight", 2)
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

  test "poster_url is nil for nil" do
    assert TMDB.poster_url(nil) == nil
  end

  test "poster_url returns absolute path for URL" do
    assert TMDB.poster_url("/poster.jpg") == "https://image.tmdb.org/t/p/w342/poster.jpg"
  end
end
