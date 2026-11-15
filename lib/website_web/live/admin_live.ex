defmodule PortfolioWeb.AdminLive do
  use PortfolioWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Admin</.header>
      <p class="text-zinc-600">Nothing here yet.</p>
    </Layouts.app>
    """
  end
end
