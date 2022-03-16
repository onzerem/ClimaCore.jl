using ClimaCorePlots, Plots

include("baroclinic_wave_utilities.jl")

const sponge = false

# Variables required for driver.jl (modify as needed)
space = ExtrudedSpace(;
    zmax = FT(30e3),
    zelem = 10,
    hspace = CubedSphere(; radius = R, helem = 4, npoly = 4),
)
t_end = FT(60 * 60 * 24 * 10)
dt = FT(400)
dt_save_to_sol = FT(60 * 60 * 24)
dt_save_to_disk = FT(0) # 0 means don't save to disk
ode_algorithm = OrdinaryDiffEq.Rosenbrock23
jacobian_flags = (; ∂𝔼ₜ∂𝕄_mode = :exact, ∂𝕄ₜ∂ρ_mode = :exact)

initial_condition(local_geometry) = initial_condition_ρθ(local_geometry)
initial_condition_velocity(local_geometry) =
    initial_condition_velocity(local_geometry; is_balanced_flow = false)

remaining_cache_values(Y, dt) = merge(
    baroclinic_wave_cache_values(Y, dt),
    held_suarez_cache_values(Y, dt),
    final_adjustments_cache_values(Y, dt; use_rayleigh_sponge = sponge),
)

function remaining_tendency!(dY, Y, p, t)
    dY .= zero(eltype(dY))
    held_suarez_ρθ_tempest_remaining_tendency!(dY, Y, p, t; κ₄ = 2.0e17)
    held_suarez_forcing!(dY, Y, p, t)
    final_adjustments!(
        dY,
        Y,
        p,
        t;
        use_flux_correction = false,
        use_rayleigh_sponge = sponge,
    )
    return dY
end

function postprocessing(sol, p, output_dir)
    @info "L₂ norm of ρθ at t = $(sol.t[1]): $(norm(sol.u[1].Yc.ρθ))"
    @info "L₂ norm of ρθ at t = $(sol.t[end]): $(norm(sol.u[end].Yc.ρθ))"

    anim = Plots.@animate for Y in sol.u
        v = Geometry.UVVector.(Y.uₕ).components.data.:2
        Plots.plot(v, level = 3, clim = (-6, 6))
    end
    Plots.mp4(anim, joinpath(output_dir, "v.mp4"), fps = 5)
end
