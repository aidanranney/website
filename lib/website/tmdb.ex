defmodule Portfolio.TMDB do
  @moduledoc """
  Client for The Movie Database (TMDB) API.

  The base URL for images defaults to TMDB's long-stable CDN location.
  If this ever changes, its configuration can be overridden:

      config :website, Portfolio.TMDB, image_base: "https://image.tmdb.org/t/p/"

  **Note**: TMDB terms require attribution on any page that displays its data.
  """

  @base_url "https://api.themoviedb.org/3"
  @default_image_base "https://image.tmdb.org/t/p/"
  @poster_size "w342"

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
  Searches movies by title for a 1-based `page`, returning normalized results
  together with TMDB's paging metadata so callers can load subsequent pages.
  """
  @spec search(String.t(), pos_integer()) ::
          {:ok, %{movies: [movie()], page: integer(), total_pages: integer()}}
          | {:error, term()}
  def search(query, page \\ 1) when is_binary(query) and is_integer(page) and page > 0 do
    if String.trim(query) == "" do
      {:ok, %{movies: [], page: 0, total_pages: 0}}
    else
      handle_search(query, page)
    end
  end

  defp handle_search(query, page) do
    with :ok <- ensure_configured(),
         {:ok, response} <-
           Req.get(client(),
             url: "/search/movie",
             params: [query: query, include_adult: false, page: page]
           ) do
      case response.status do
        200 ->
          body = response.body

          {:ok,
           %{
             movies: Enum.map(body["results"] || [], &normalize_movie/1),
             page: body["page"] || page,
             total_pages: body["total_pages"] || page
           }}

        status ->
          {:error, {:http, status}}
      end
    end
  end

  @doc """
  Fetches one movie's details. A missing movie returns `{:error, :not_found}`.
  """
  @spec get_movie(binary()) :: {:ok, movie()} | {:error, :not_found | {:http, integer()}}
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
  poster.
  """
  @spec poster_url(String.t()) :: String.t() | nil
  def poster_url(nil), do: nil
  def poster_url(""), do: nil

  def poster_url(path) when is_binary(path) do
    "#{image_base()}#{@poster_size}#{path}"
  end

  defp ensure_configured do
    if configured?(), do: :ok, else: {:error, :not_configured}
  end

  defp client do
    [
      base_url: @base_url,
      headers: [authorization: "Bearer #{token()}"],
      receive_timeout: 5_000,
      # A 429 must reach the UI immediately so it can render fallback cards.
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config(), :req_options, []))
    |> Req.new()
  end

  defp config, do: Application.get_env(:website, __MODULE__, [])

  defp token, do: Keyword.get(config(), :token)

  defp image_base do
    config()
    |> Keyword.get(:image_base, @default_image_base)
    |> String.trim_trailing("/")
    |> Kernel.<>("/")
  end

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
end
