defmodule PortfolioWeb.Plugs.WwwRedirectTest do
  use PortfolioWeb.ConnCase, async: true

  alias PortfolioWeb.Plugs.WwwRedirect

  defp call(host, path) do
    %{Phoenix.ConnTest.build_conn(:get, path) | host: host}
    |> WwwRedirect.call([])
  end

  test "redirects www of the canonical host to apex, preserving path and query" do
    apex = PortfolioWeb.Endpoint.host()
    conn = call("www." <> apex, "/movies?page=2")

    assert conn.halted
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://#{apex}/movies?page=2"]
  end

  test "redirects the fly.dev hostname to apex" do
    apex = PortfolioWeb.Endpoint.host()
    conn = call("asr-website.fly.dev", "/")

    assert conn.halted
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://#{apex}/"]
  end

  test "passes the canonical host through untouched" do
    conn = call(PortfolioWeb.Endpoint.host(), "/")

    refute conn.halted
    assert conn.status == nil
  end

  test "passes unrelated hosts (e.g. test/dev hosts) through untouched" do
    conn = call("www.example.com", "/")

    refute conn.halted
    assert conn.status == nil
  end
end
