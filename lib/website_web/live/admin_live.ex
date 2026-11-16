defmodule PortfolioWeb.AdminLive do
  use PortfolioWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Admin</.header>
      <ul>
        <li><.link navigate={~p"/admin/movie-nights"}>Manage movie nights</.link></li>
      </ul>
    </Layouts.app>
    """
  end
end
