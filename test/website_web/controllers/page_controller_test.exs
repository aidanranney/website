defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase

  import Portfolio.AccountsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Aidan Ranney"
  end

  test "GET /about renders", %{conn: conn} do
    assert conn |> get(~p"/about") |> html_response(200) =~ "About"
  end

  test "GET /contact renders a mailto link", %{conn: conn} do
    assert conn |> get(~p"/contact") |> html_response(200) =~ "mailto:"
  end

  test "navbar shows the brand and public links", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Aidan Ranney"
    assert html =~ ~s(href="/about")
    assert html =~ ~s(href="/contact")
  end

  test "navbar shows log in and register when signed out", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="/users/log-in")
    assert html =~ ~s(href="/users/register")
    refute html =~ ~s(href="/users/settings")
  end

  test "navbar shows settings and log out when signed in", %{conn: conn} do
    html = conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="/users/settings")
    assert html =~ "Log out"
    refute html =~ ~s(href="/users/log-in")
  end
end
