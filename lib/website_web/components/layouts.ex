defmodule PortfolioWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PortfolioWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false, doc: "use the wider content column"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-zinc-200">
      <div class="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
        <a href={~p"/"} class="text-sm font-semibold tracking-tight text-zinc-900">
          Aidan Ranney
        </a>

        <nav class="flex items-center gap-6 text-sm text-zinc-600">
          <.link navigate={~p"/about"} class="transition-colors hover:text-zinc-900">About</.link>
          <.link navigate={~p"/contact"} class="transition-colors hover:text-zinc-900">
            Contact
          </.link>
          <span class="h-4 w-px bg-zinc-200" aria-hidden="true"></span>
          <%= if @current_scope && @current_scope.user do %>
            <.link href={~p"/movie-night"} class="transition-colors hover:text-zinc-900">
              Movie night
            </.link>
            <.link href={~p"/users/settings"} class="transition-colors hover:text-zinc-900">
              Settings
            </.link>
            <.link
              :if={Portfolio.Accounts.Scope.admin?(@current_scope)}
              href={~p"/admin"}
              class="transition-colors hover:text-zinc-900"
            >
              Admin
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="transition-colors hover:text-zinc-900"
            >
              Log out
            </.link>
          <% else %>
            <.link href={~p"/users/log-in"} class="transition-colors hover:text-zinc-900">
              Log in
            </.link>
            <.link href={~p"/users/register"} class="transition-colors hover:text-zinc-900">
              Register
            </.link>
          <% end %>
        </nav>
      </div>
    </header>

    <main class={["mx-auto px-6 py-16 sm:py-24", if(@wide, do: "max-w-5xl", else: "max-w-2xl")]}>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
