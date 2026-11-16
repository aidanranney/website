defmodule Portfolio.TMDB do
  @moduledoc """
  A thin client for The Movie Database (TMDB) API.

  Only `tmdb_id` values are persisted; movie details are fetched here at render
  time. Configuration lives under `config :website, Portfolio.TMDB`:

      config :website, Portfolio.TMDB, token: "..."
      config :website, Portfolio.TMDB, req_options: [plug: {Req.Test, Portfolio.TMDB}]

  TMDB terms require attribution on any page that displays its data; see the
  movie-night LiveViews for the notice and logo.
  """

  @base_url "https://api.themoviedb.org/3"
  @fallback_image_base "https://image.tmdb.org/t/p/"
  @image_cache_key {__MODULE__, :image_base}

  @type movie :: %{
          tmdb_id: integer(),
          title: String.t(),
          year: integer() | nil,
          overview: String.t() | nil,
          poster_path: String.t() | nil
        }

  @doc "Whether a TMDB read token is configured."
  def configured?, do: is_binary(token()) and token() != ""

  @doc """
  Searches movies by title, returning a normalized list of results.
  """
  def search(query) when is_binary(query) do
    if String.trim(query) == "" do
      {:ok, []}
    else
      with :ok <- ensure_configured(),
           {:ok, response} <- Req.get(client(), url: "/search/movie", params: [query: query]) do
        case response.status do
          200 -> {:ok, Enum.map(response.body["results"] || [], &normalize_movie/1)}
          status -> {:error, {:http, status}}
        end
      end
    end
  end

  @doc """
  Fetches one movie's details. A missing movie returns `{:error, :not_found}`.
  """
  def get_movie(tmdb_id) do
    with :ok <- ensure_configured(),
         {:ok, response} <- Req.get(client(), url: "/movie/#{tmdb_id}") do
      case response.status do
        200 -> {:ok, normalize_movie(response.body)}
        404 -> {:error, :not_found}
        status -> {:error, {:http, status}}
      end
    end
  end

  @doc """
  Builds a `w342` poster URL for a TMDB poster path, or nil when there is no
  poster. The image base URL is cached for the life of the VM.
  """
  def poster_url(nil), do: nil
  def poster_url(""), do: nil

  def poster_url(path) when is_binary(path) do
    "#{image_base()}w342#{path}"
  end

  defp ensure_configured do
    if configured?(), do: :ok, else: {:error, :not_configured}
  end

  defp client do
    config = Application.get_env(:website, __MODULE__, [])

    [
      base_url: @base_url,
      headers: [authorization: "Bearer #{token()}"],
      receive_timeout: 5_000,
      # A 429 must reach the UI immediately so it can render fallback cards.
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.new()
  end

  defp token, do: Application.get_env(:website, __MODULE__, []) |> Keyword.get(:token)

  defp normalize_movie(movie) do
    %{
      tmdb_id: movie["id"],
      title: movie["title"] || movie["name"] || "Untitled",
      year: year(movie["release_date"]),
      overview: movie["overview"],
      poster_path: movie["poster_path"]
    }
  end

  defp year(<<year::binary-size(4), _::binary>>) do
    case Integer.parse(year) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp year(_), do: nil

  defp image_base do
    case :persistent_term.get(@image_cache_key, nil) do
      nil -> fetch_image_base()
      base -> base
    end
  end

  defp fetch_image_base do
    base =
      if configured?() do
        case Req.get(client(), url: "/configuration") do
          {:ok, %{status: 200, body: %{"images" => %{"secure_base_url" => url}}}}
          when is_binary(url) ->
            if String.ends_with?(url, "/"), do: url, else: url <> "/"

          _ ->
            @fallback_image_base
        end
      else
        @fallback_image_base
      end

    :persistent_term.put(@image_cache_key, base)
    base
  end
end
