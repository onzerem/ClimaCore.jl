ENV["CLIMACOMMS_DEVICE"] = "CUDA"; # requires cuda
using LazyBroadcast: lazy
using ClimaCore.Utilities: half
using Test, ClimaComms
ClimaComms.@import_required_backends;
using ClimaCore: Geometry, Spaces, Fields, Operators, ClimaCore;
using ClimaCore: Utilities, DataLayouts
using ClimaCore.CommonSpaces;
import ClimaCore.Geometry: ⊗

get_space_extruded(dev, FT; z_elem = 63, h_elem = 30) =
    ExtrudedCubedSphereSpace(
        FT;
        device = dev,
        z_elem,
        z_min = 0,
        z_max = 1,
        radius = 10,
        h_elem,
        n_quad_points = 4,
        staggering = CellCenter(),
    );

get_space_plane(dev, FT; z_elem = 100) = SliceXZSpace(
    FT;
    device = dev,
    z_elem,
    x_min = 0,
    x_max = 100000,
    z_min = 0,
    z_max = 21000,
    periodic_x = false,
    n_quad_points = 4,
    x_elem = 100,
    staggering = CellCenter(),
);

get_space_column(dev, FT; z_elem = 10) = ColumnSpace(
    FT;
    device = dev,
    z_elem = z_elem,
    z_min = 0,
    z_max = 1,
    staggering = CellCenter(),
);

function test_face_windows(Base.@nospecialize(bc))
    ext = Base.get_extension(ClimaCore, :ClimaCoreCUDAExt)
    @test bc isa Operators.StencilBroadcasted
    space = axes(bc)
    ᶜspace = Spaces.center_space(space)
    arg_space = ext.get_arg_space(bc, bc.args)
    bc_bds = Operators.window_bounds(space, bc)
    for lev in 1:(Spaces.nlevels(ᶜspace) + 1)
        idx = (lev - half)::Utilities.PlusHalf
        args = (idx, arg_space, bc_bds, bc.op, bc.args...)
        B = (
            ext.in_left_boundary_window(args...),
            ext.in_interior(args...),
            ext.in_right_boundary_window(args...),
        )
        count(B) == 1 || @show idx, B
        @test count(B) == 1
    end
end

@inline function test_center_windows(Base.@nospecialize(bc))
    ext = Base.get_extension(ClimaCore, :ClimaCoreCUDAExt)
    @test bc isa Operators.StencilBroadcasted
    space = axes(bc)
    ᶜspace = Spaces.center_space(space)
    arg_space = ext.get_arg_space(bc, bc.args)
    bc_bds = Operators.window_bounds(space, bc)
    for idx in 1:Spaces.nlevels(ᶜspace)
        args = (idx, arg_space, bc_bds, bc.op, bc.args...)
        B = (
            ext.in_left_boundary_window(args...),
            ext.in_interior(args...),
            ext.in_right_boundary_window(args...),
            idx == Spaces.nlevels(ᶜspace) + 1,
        )
        count(B) == 1 || @show idx, B
        @test count(B) == 1
    end
end

function kernels!(fields)
    (; f, ρ, ϕ) = fields
    (; ᶜout1, ᶜout2, ᶜout3, ᶜout4, ᶜout5, ᶜout6, ᶜout7, ᶜout8, ᶜout9) = fields
    (; ᶜout10, ᶜout11, ᶜout12, ᶜout13, ᶜout14) = fields
    (; ᶠout1, ᶠout2) = fields
    (; ᶠout1_contra, ᶠout2_contra) = fields
    (; ᶠout3_cov, ᶠout4_cov, ᶠout5_cov) = fields
    (; w_cov) = fields
    (; ᶜout_uₕ, ᶜuₕ) = fields
    FT = Spaces.undertype(axes(ϕ))
    div_bcs = Operators.DivergenceF2C(;
        bottom = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
        top = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
    )
    div = Operators.DivergenceF2C()
    ᶠwinterp = Operators.WeightedInterpolateC2F(
        bottom = Operators.Extrapolate(),
        top = Operators.Extrapolate(),
    )
    @. ᶜout1 = div(Geometry.WVector(f))
    @. ᶜout2 = 0
    @. ᶜout2 += div(Geometry.WVector(f) * 2)
    @. ᶜout3 = div(Geometry.WVector(ᶠwinterp(ϕ, ρ)))

    @. ᶜout4 = div_bcs(Geometry.WVector(f))
    @. ᶜout5 = 0
    @. ᶜout5 += div_bcs(Geometry.WVector(f) * 2)
    @. ᶜout6 = div_bcs(Geometry.WVector(ᶠwinterp(ϕ, ρ)))

    # from the wild
    Ic2f = Operators.InterpolateC2F(; top = Operators.Extrapolate())
    divf2c = Operators.DivergenceF2C(;
        bottom = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
    )
    # only upward component of divergence
    @. ᶜout7 = divf2c(Geometry.WVector(Ic2f(ϕ)))
    @. ᶜout8 = divf2c(Ic2f(Geometry.WVector(ϕ)))

    upwind = Operators.UpwindBiasedProductC2F(;
        bottom = Operators.SetValue(FT(0)),
        top = Operators.SetValue(FT(0)),
    )
    @. ᶠout1_contra = upwind(w_cov, ϕ)

    upwind = Operators.UpwindBiasedProductC2F(;
        bottom = Operators.Extrapolate(),
        top = Operators.Extrapolate(),
    )
    @. ᶠout2_contra = upwind(w_cov, ϕ)

    upwind = Operators.Upwind3rdOrderBiasedProductC2F(;
        # bottom = Operators.ThirdOrderOneSided(),
        # top = Operators.ThirdOrderOneSided()
        bottom = Operators.FirstOrderOneSided(),
        top = Operators.FirstOrderOneSided(),
    )
    outer = (;
        bottom = Operators.SetValue(Geometry.Contravariant3Vector(FT(0.0))),
        top = Operators.SetValue(Geometry.Contravariant3Vector(FT(0.0))),
    )
    divf2c = Operators.DivergenceF2C(outer)
    @. ᶜout9 = divf2c(upwind(w_cov, ϕ))

    divf2c_vl = Operators.DivergenceF2C(
        bottom = Operators.SetValue(Geometry.WVector(FT(10))),
        top = Operators.SetValue(Geometry.WVector(FT(10))),
    )
    limiter_method = Operators.AlgebraicMean()
    VanLeerMethod = Operators.LinVanLeerC2F(
        bottom = Operators.FirstOrderOneSided(),
        top = Operators.FirstOrderOneSided(),
        constraint = limiter_method,
    )
    Δt = FT(1)
    @. ᶜout10 = -divf2c_vl(VanLeerMethod(w_cov, ϕ, Δt))

    inner = (;)
    outer = set_value_divgrad_uₕ_maybe_field_bcs(axes(ϕ))

    grad = Operators.GradientC2F(inner)
    div_uh = Operators.DivergenceF2C(outer)
    @. ᶜout_uₕ = div_uh(f * grad(ᶜuₕ))

    ᶠgrad = Operators.GradientC2F(;
        bottom = Operators.SetValue(FT(10)),
        top = Operators.SetValue(FT(10)),
    )
    @. ᶠout3_cov = ᶠgrad(ϕ)

    ᶠgrad = Operators.GradientC2F(;
        bottom = Operators.SetValue(FT(10)),
        top = Operators.SetValue(FT(10)),
    )
    ᶜinterp = Operators.InterpolateF2C()
    ᶠinterp = Operators.InterpolateC2F(
        bottom = Operators.Extrapolate(),
        top = Operators.Extrapolate(),
    )
    @. ᶠout4_cov = ᶠgrad(ᶜinterp(f))
    @. ᶠout2 = ᶠinterp(ᶜinterp(f)) # exercises very nested operation
    @. ᶠout5_cov = ᶠgrad(ᶜinterp(ᶠinterp(ᶜinterp(f)))) # exercises very nested operation
    @. ᶜout14 = ᶜinterp(ᶠinterp(ᶜinterp(f))) # exercises very nested operation

    @. ᶠout4_cov = ᶠgrad(ᶜinterp(f))
    ᶜdiv = Operators.DivergenceF2C(
        bottom = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
        top = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
    )
    @. ᶜout13 = ᶜdiv(Geometry.WVector(ᶠinterp(ᶜinterp(f)))) # exercises very nested operation

    ᶠgrad_top_bcs = Operators.GradientC2F(; top = Operators.SetValue(FT(10)))
    divf2c = Operators.DivergenceF2C(
        bottom = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
    )
    @. ᶜout11 = 0
    @. ᶜout11 += divf2c(ᶠgrad_top_bcs(ϕ))

    ᶠgrad_no_bc = Operators.GradientC2F()
    div_bcs = Operators.DivergenceF2C(;
        bottom = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
        top = Operators.SetValue(Geometry.Covariant3Vector(FT(10))),
    )
    @. ᶜout12 = 0
    @. ᶜout12 += div_bcs(ᶠgrad_no_bc(ϕ))

    ᶠinterp = Operators.InterpolateC2F(
        bottom = Operators.Extrapolate(),
        top = Operators.Extrapolate(),
    )
    @. ᶠout1 = ᶠinterp(ϕ)

    return nothing
end;

function get_fields(space::Operators.AllFaceFiniteDifferenceSpace)
    FT = Spaces.undertype(space)
    (; z) = Fields.coordinate_field(space)
    K = (:f,)
    V = ntuple(i -> Fields.zeros(space), length(K))
    K_contra = (ntuple(i -> Symbol("ᶠout$(i)_contra"), 8)...,)
    V_contra = ntuple(
        i -> Fields.Field(Geometry.Contravariant3Vector{FT}, space),
        length(K_contra),
    )
    K_scalar = (ntuple(i -> Symbol("ᶠout$(i)"), 3)...,)
    V_scalar = ntuple(i -> Fields.Field(FT, space), length(K_scalar))
    K_cov_out = (ntuple(i -> Symbol("ᶠout$(i)_cov"), 8)...,)
    V_cov_out = ntuple(
        i -> Fields.zeros(Geometry.Covariant3Vector{FT}, space),
        length(K_cov_out),
    )
    K_cov = (:w_cov,)
    V_cov = ntuple(
        i -> Fields.Field(Geometry.Covariant3Vector{FT}, space),
        length(K_cov),
    )
    nt = (;
        zip(K, V)...,
        zip(K_scalar, V_scalar)...,
        zip(K_contra, V_contra)...,
        zip(K_cov, V_cov)...,
        zip(K_cov_out, V_cov_out)...,
    )
    @. nt.f = sin(z)
    @. nt.w_cov.components.data.:1 = sin(z)
    return nt
end

function get_fields(space::Operators.AllCenterFiniteDifferenceSpace)
    FT = Spaces.undertype(space)
    K = (ntuple(i -> Symbol("ᶜout$i"), 14)..., :ρ, :ϕ)
    V = ntuple(i -> Fields.zeros(space), length(K))
    nt = (;
        zip(K, V)...,
        ᶜout_uₕ = Fields.Field(Geometry.Covariant12Vector{FT}, space),
        ᶜuₕ = Fields.Field(Geometry.Covariant12Vector{FT}, space),
    )
    (; z) = Fields.coordinate_field(space)
    @. nt.ρ = sin(z)
    @. nt.ϕ = sin(z)
    @. nt.ᶜout_uₕ.components.data.:1 = 0
    @. nt.ᶜout_uₕ.components.data.:2 = 0
    @. nt.ᶜuₕ.components.data.:1 = sin(z)
    @. nt.ᶜuₕ.components.data.:2 = sin(z)
    return nt
end

function set_value_divgrad_uₕ_bcs(space) # real-world example
    FT = Spaces.undertype(space)
    top_val =
        Geometry.Contravariant3Vector(FT(0)) ⊗
        Geometry.Covariant12Vector(FT(0), FT(0))
    bottom_val =
        Geometry.Contravariant3Vector(FT(0)) ⊗
        Geometry.Covariant12Vector(FT(0), FT(0))
    return (;
        top = Operators.SetValue(top_val),
        bottom = Operators.Extrapolate(),
    )
end

function set_value_divgrad_uₕ_maybe_field_bcs(space) # real-world example
    FT = Spaces.undertype(space)
    top_val =
        Geometry.Contravariant3Vector(FT(0)) ⊗
        Geometry.Covariant12Vector(FT(0), FT(0))
    if hasproperty(space, :horizontal_space)
        z_bottom = Spaces.level(Fields.coordinate_field(space).z, 1)
        bottom_val =
            Geometry.Contravariant3Vector.(zeros(axes(z_bottom))) .⊗
            Geometry.Covariant12Vector.(
                zeros(axes(z_bottom)),
                zeros(axes(z_bottom)),
            )
        return (;
            top = Operators.SetValue(top_val),
            bottom = Operators.SetValue(.-bottom_val),
        )
    else
        return (;
            top = Operators.SetValue(top_val),
            bottom = Operators.SetValue(top_val),
        )
    end
end


function compare_cpu_gpu(cpu, gpu; print_diff = true, C_best = 10)
    # there are some odd errors that build up when run without debug / bounds checks:
    space = axes(cpu)
    are_boundschecks_forced = Base.JLOptions().check_bounds == 1
    absΔ = abs.(parent(cpu) .- Array(parent(gpu)))
    max_allowed_err = if space isa Spaces.FiniteDifferenceSpace
        are_boundschecks_forced ? 1000 * eps() : 10000000 * eps()
    else
        1e-9
    end
    max_err = maximum(absΔ)
    gpu_matches_cpu = max_err <= max_allowed_err
    gpu_matches_cpu || @show max_err
    z = Fields.field_values(Fields.coordinate_field(space))
    C = count(x -> x <= max_allowed_err, absΔ)
    if !gpu_matches_cpu && print_diff
        N = 3
        if z isa DataLayouts.VF
            @show parent(cpu)[1:N]
            @show parent(gpu)[1:N]
            @show parent(cpu)[(end - N):end]
            @show parent(gpu)[(end - N):end]
        elseif z isa DataLayouts.VIJFH
            @show parent(cpu)[1:N, 1, 1, 1, end]
            @show parent(gpu)[1:N, 1, 1, 1, end]
            @show parent(cpu)[(end - N):end, 1, 1, 1, end]
            @show parent(gpu)[(end - N):end, 1, 1, 1, end]
        elseif z isa DataLayouts.VIFH
            @show parent(cpu)[1:N, 1, 1, end]
            @show parent(gpu)[1:N, 1, 1, end]
            @show parent(cpu)[(end - N):end, 1, 1, end]
            @show parent(gpu)[(end - N):end, 1, 1, end]
        else
            error("Unsupported type: $(typeof(z))")
        end
    end
    return gpu_matches_cpu
end

# This function is useful for debugging new cases.
function compare_cpu_gpu_incremental(cpu, gpu; print_diff = true, C_best = 10)
    # there are some odd errors that build up when run without debug / bounds checks:
    space = axes(cpu)
    z = Fields.field_values(Fields.coordinate_field(space))
    are_boundschecks_forced = Base.JLOptions().check_bounds == 1
    absΔ = abs.(parent(cpu) .- Array(parent(gpu)))
    max_err = are_boundschecks_forced ? 10000 * eps() : 10000000 * eps()
    B = maximum(absΔ) <= max_err
    C = count(x -> x <= max_err, absΔ)
    @test C ≥ C_best
    if !(C_best == 10)
        C > C_best && @show C_best
        @test_broken C > C_best
    end
    if !B && print_diff
        if z isa DataLayouts.VF
            @show parent(cpu)[1:3]
            @show parent(gpu)[1:3]
            @show parent(cpu)[(end - 3):end]
            @show parent(gpu)[(end - 3):end]
        elseif z isa DataLayouts.VIJFH
            @show parent(cpu)[1:3, 1, 1, 1, end]
            @show parent(gpu)[1:3, 1, 1, 1, end]
            @show parent(cpu)[(end - 3):end, 1, 1, 1, end]
            @show parent(gpu)[(end - 3):end, 1, 1, 1, end]
        elseif z isa DataLayouts.VIJFH
            @show parent(cpu)[1:3, 1, 1, end]
            @show parent(gpu)[1:3, 1, 1, end]
            @show parent(cpu)[(end - 3):end, 1, 1, end]
            @show parent(gpu)[(end - 3):end, 1, 1, end]
        else
            error("Unsupported type: $(typeof(z))")
        end
    end
    return true
end

is_trivial(x) = length(parent(x)) == count(iszero, parent(x)) # Make sure we don't have a trivial solution

nothing
