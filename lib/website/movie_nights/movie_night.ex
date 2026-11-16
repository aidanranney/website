defmodule Portfolio.MovieNights.MovieNight do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "movie_nights" do
    field :starts_at, :naive_datetime
    field :note, :string
    field :phase, :string, default: "nominating"

    has_many :candidates, Portfolio.MovieNights.Candidate

    timestamps(type: :utc_datetime)
  end

  def changeset(movie_night, attrs) do
    movie_night
    |> cast(attrs, [:starts_at, :note])
    |> validate_required([:starts_at])
    |> validate_inclusion(:phase, ~w(nominating voting done))
  end
end
