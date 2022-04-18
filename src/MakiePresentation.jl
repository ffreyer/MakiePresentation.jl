module MakiePresentation

using Makie

# Testing utility
const lorem_ipsum = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."


mutable struct Presentation
    parent::Figure
    fig::Figure

    idx::Int
    slides::Vector{Function}
end

"""
    Presentation(; kwargs...)

Creates a `pres::Presentation` with two figures `pres.parent` and `pres.fig`. 
The former remains static during the presentation and acts as the background and 
window.  The latter acts as the slide and gets cleared and reassambled every 
time a new slide is requested. (This includes events.)

To add a slide use:

    add_slide!(pres) do fig
        # Plot your slide to fig
    end

Note that `add_slide!` immediately switches to and draws the newly added slide. 
This is done to get rid of compilation times beforehand.

To switch to a different slide:
- `next_slide!(pres)`: Advance to the next slide. Default keys: Keyboard.right, Keyboard.enter
- `previous_slide!(pres)`: Go to the previous slide. Default keys: Keyboard.left
- `reset!(pres)`: Go to the first slide. Defaults keys: Keyboard.home
- `set_slide_idx!(pres, idx)`: Go a specified slide.

"""
function Presentation(; kwargs...)
    # This is a modified version of the Figure() constructor.
    parent = Figure(; kwargs...)

    kwargs_dict = Dict(kwargs)
    padding = pop!(kwargs_dict, :figure_padding, Makie.current_default_theme()[:figure_padding])

    # Separate events from the parent (static background) and slide figure so
    # that slide events can be cleared without clearing slide events (like 
    # moving to the next slide)
    separated_events = Events()
    _events = parent.scene.events
    for fieldname in fieldnames(Events)
        obs = getfield(separated_events, fieldname)
        if obs isa Makie.PriorityObservable
            on(v -> obs[] = v, getfield(_events, fieldname), priority = 100)
        end
    end

    scene = Scene(
        parent.scene; camera=campixel!, clear = false, 
        events = separated_events, kwargs_dict...
    )

    padding = padding isa Observable ? padding : Observable{Any}(padding)
    alignmode = lift(Outside ∘ Makie.to_rectsides, padding)

    layout = Makie.GridLayout(scene)

    on(alignmode) do al
        layout.alignmode[] = al
        Makie.GridLayoutBase.update!(layout)
    end
    notify(alignmode)

    f = Figure(
        scene,
        layout,
        [],
        Attributes(),
        Ref{Any}(nothing)
    )
    layout.parent = f

    p = Presentation(parent, f, 1, Function[])

    # Interactions
    on(events(parent.scene).keyboardbutton, priority = -1) do event
        if event.action == Keyboard.release
            if event.key in (Keyboard.right, Keyboard.enter)
                next_slide!(p)
            elseif event.key in (Keyboard.left,)
                previous_slide!(p)
            elseif event.key in (Keyboard.home,)
                reset!(p)
            end
        end
    end

    return p
end

Base.display(p::Presentation) = display(p.parent)
Base.getindex(p::Presentation, idxs...) = getindex(p.fig, idxs...)
Base.empty!(p::Presentation) = empty!(p.fig)

function set_slide_idx!(p::Presentation, i)
    if i != p.idx && (1 <= i <= length(p.slides))
        p.idx = i
        empty!(p.fig)
        p.slides[p.idx](p)
    end
    return
end

next_slide!(p::Presentation) = set_slide_idx!(p, p.idx + 1)
previous_slide!(p::Presentation) = set_slide_idx!(p, p.idx - 1)
reset!(p::Presentation) = set_slide_idx!(p, 1)

function add_slide!(f::Function, p)
    # To avoid compile time during presentation we should probably actually 
    # generate these plots...
    # That also validates that they work
    try
        f(p)
        push!(p.slides, f)
        p.idx = length(p.slides)
    catch e
        @error "Failed to add slide - maybe the function signature does not match f(::Presentation)?"
        rethrow(e)
    end
    return
end

export Presentation
export add_slide!, set_slide_idx!, next_slide!, previous_slide!, reset!

end
