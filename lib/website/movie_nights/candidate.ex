defmodule Portfolio.MovieNights.Candidate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "candidates" do
    belongs_to :movie_night, Portfolio.MovieNights.MovieNight
    belongs_to :nominated_by, Portfolio.Accounts.User
    field :tmdb_id, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:tmdb_id])
    |> validate_required([:tmdb_id])
    |> unique_constraint([:movie_night_id, :tmdb_id])
  end
end
