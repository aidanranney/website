defmodule PortfolioWeb.PageController do
  use PortfolioWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home")
  end

  def about(conn, _params) do
    render(conn, :about, page_title: "About")
  end

  def projects(conn, _params) do
    render(conn, :projects, page_title: "Projects")
  end

  def contact(conn, _params) do
    render(conn, :contact, page_title: "Contact")
  end
end
