defmodule Reservations.Event do
  use Reservations.Web, :model
  alias Reservations.Event

  schema "events" do
    field :name, :string
    field :start_date, Ecto.Date
    field :end_date, Ecto.Date

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast_params(params)
    # I split these like this to make it easy to test constraints and
    # validations separately, or just comment out `run_validations`
    |> run_validations
    |> prepare_for_constraints
  end

  def cast_params(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :start_date, :end_date])
  end

  def run_validations(struct) do
    struct
    |> validate_in_memory
    |> unsafe_validate_against_repo
  end

  def validate_in_memory(struct) do
    struct
    |> validate_required([:name, :start_date, :end_date])
    |> validate_positive_duration
  end

  # These validations are "unsafe" because they can't prevent race conditions;
  # we must also have constraints to reliably prevent conflicting data.
  # But in most cases, these will enable a user to fix conflicting data at the
  # same time that they correct (eg) blank fields.
  def unsafe_validate_against_repo(struct) do
    struct
    |> validate_no_conflicts_unreliably(:name, &find_conflicting_names/1, "has already been taken")
    |> validate_no_conflicts_unreliably(:base, &find_overlapping_dates/1, "may not overlap another event")
  end

  def prepare_for_constraints(struct) do
    struct
    |> unique_constraint(:name)
    |> exclusion_constraint(:base, name: :no_overlaps, message: "cannot overlap dates with another event")
  end

  def validate_positive_duration(changeset) do
    if get_field(changeset, :start_date) <= get_field(changeset, :end_date) do
      changeset
    else
      add_error(
      changeset,
      :base,
      "start date cannot be before end date",
      [validation: :validate_positive_duration]
      )
    end
  end

  def validate_no_conflicts_unreliably(changeset, field_name, conflict_finder_func, error_message) do
    conflicts = conflict_finder_func.(changeset)

    if Enum.any?(conflicts) do
      add_error(
                changeset,
                field_name,
                error_message,
                [validation: :validate_no_conflicts_unreliably]
              )
    else
      changeset
    end
  end

  defp find_conflicting_names(changeset) do
    name = get_field(changeset, :name)
    if is_nil(name) do
      []
    else
      dups_query = from e in Event, where: e.name == ^name

      # For updates, don't flag event as a dup of itself
      id = get_field(changeset, :id)
      dups_query = if is_nil(id) do
        dups_query
      else
        from e in dups_query, where: e.id != ^id
      end

      Reservations.Repo.all(dups_query)
    end
  end

  defp find_overlapping_dates(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)
    if is_nil(start_date) or is_nil(end_date) do
      []
    else

      overlap_query = Event
      |> Reservations.Event.Scopes.overlapping(start_date, end_date)

      # For updates, don't flag event as overlapping itself
      id = get_field(changeset, :id)
      overlap_query = if is_nil(id) do
        overlap_query
      else
        from e in overlap_query, where: e.id != ^id
      end

      Reservations.Repo.all(overlap_query)
    end
  end

end
