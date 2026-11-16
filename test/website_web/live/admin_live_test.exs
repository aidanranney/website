defmodule PortfolioWeb.AdminLiveTest do
  use PortfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolio.AccountsFixtures

  test "redirects logged-out visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
  end

  test "redirects non-admin users home", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
  end

  test "renders for admins", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())
    {:ok, _lv, html} = live(conn, ~p"/admin")
    assert html =~ "Admin"
  end
end
