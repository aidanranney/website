defmodule PortfolioWeb.Plugs.WwwRedirect do
  @moduledoc """
  Permanently redirects non-canonical hosts to the canonical apex host over
  HTTPS, so `aidanranney.com` (PHX_HOST) is the single address users and search
  engines see. Covers `www.<apex>` and the Fly-assigned `*.fly.dev` hostname.
  Other hosts (localhost in dev, test hosts) pass through untouched.
  """
  import Plug.Conn

  alias PortfolioWeb.Endpoint

  def init(opts), do: opts

  def call(%Plug.Conn{host: host} = conn, _opts) do
    apex = Endpoint.host()

    if host != apex and (host == "www." <> apex or String.ends_with?(host, ".fly.dev")) do
      query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

      conn
      |> put_resp_header("location", "https://" <> apex <> conn.request_path <> query)
      |> send_resp(301, "")
      |> halt()
    else
      conn
    end
  end
end
