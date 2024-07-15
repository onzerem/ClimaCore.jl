using Logging
using Test

import ClimaCore:
    Domains,
    Fields,
    Geometry,
    Meshes,
    Operators,
    Spaces,
    Topologies,
    Quadratures

using ClimaComms
ClimaComms.@import_required_backends

# initializing MPI
const device = ClimaComms.device()
const context = ClimaComms.MPICommsContext(device)
pid, nprocs = ClimaComms.init(context)
#=
local node and face numbering
          f4
  v1o-------------o v4
    |             |
    |             |
  f1|             |f3
    |             |
    |             |
    o-------------o
   v2     f2      v3
global element numbering
-----------
|1|5| 9|13|
-----------
|2|6|10|14|
---------
|3|7|11|15|
-----------
|4|8|12|16|
-----------
partition numbers
---------
|1|1|2|3|
---------
|1|1|2|3|
---------
|1|2|2|3|
---------
|1|2|3|3|
---------
=#
@testset "4x4 element mesh with non-periodic boundaries on 3 processes" begin
    n1, n2 = 4, 4
    x1periodic, x2periodic = false, false
    Nq, Nv = 3, 1
    x1min, x1max = -2π, 2π
    x2min, x2max = -2π, 2π
    # initializing MPI
    device = ClimaComms.device()
    context = ClimaComms.MPICommsContext(device)
    pid, nprocs = ClimaComms.init(context)
    iamroot = ClimaComms.iamroot(context)
    if iamroot
        println("running test on $device device with $nprocs processes")
    end

    domain = Domains.RectangleDomain(
        Domains.IntervalDomain(
            Geometry.XPoint(x1min),
            Geometry.XPoint(x1max),
            periodic = x1periodic,
            boundary_names = x1periodic ? nothing : (:west, :east),
        ),
        Domains.IntervalDomain(
            Geometry.YPoint(x2min),
            Geometry.YPoint(x2max),
            periodic = x2periodic,
            boundary_names = x2periodic ? nothing : (:north, :south),
        ),
    )
    mesh = Meshes.RectilinearMesh(domain, n1, n2)
    topology = Topologies.Topology2D(context, mesh, Meshes.elements(mesh))
    quad = Quadratures.GLL{Nq}()
    space = Spaces.SpectralElementSpace2D(topology, quad)

    @test Topologies.nlocalelems(Spaces.topology(space)) == (pid == 1 ? 6 : 5)
    ClimaComms.allowscalar(device) do
        if pid == 1
            # gidx 1
            @test Topologies.local_neighboring_elements(
                Spaces.topology(space),
                1,
            ) == [2, 5, 6]
            @test Topologies.ghost_neighboring_elements(
                Spaces.topology(space),
                1,
            ) == []
            # gidx 6
            @test Topologies.local_neighboring_elements(
                Spaces.topology(space),
                6,
            ) == [1, 2, 3, 5]
            @test Spaces.topology(space).recv_elem_gidx[Topologies.ghost_neighboring_elements(
                Spaces.topology(space),
                6,
            )] == [7, 9, 10, 11]
        elseif pid == 2
            # gidx 7
            @test Topologies.local_neighboring_elements(
                Spaces.topology(space),
                1,
            ) == [2, 4, 5]
            @test Spaces.topology(space).recv_elem_gidx[Topologies.ghost_neighboring_elements(
                Spaces.topology(space),
                1,
            )] == [2, 3, 4, 6, 12]
        end
    end

    init_state(local_geometry, p) = (ρ = 1.0)
    y0 = init_state.(Fields.local_geometry_field(space), Ref(nothing))
    nel = Topologies.nlocalelems(Spaces.topology(space))

    yarr = parent(y0)
    yarr .=
        reshape(1:(Nq * Nq * nel), (Nq, Nq, 1, nel)) .+
        (pid - 1) * Nq * Nq * nel

    dss_buffer = Spaces.create_dss_buffer(y0)
    Spaces.weighted_dss!(y0, dss_buffer) # DSS2

#! format: off
    if pid == 1
        @test Array(yarr[:]) == [1.0, 2.0, 6.5, 4.0, 5.0, 9.5, 22.0, 23.0, 27.5, 6.5, 11.0, 15.5, 9.5, 14.0, 18.5, 27.5, 32.0, 34.25,
                       15.5, 20.0, 24.5, 18.5, 23.0, 27.5, 34.25, 36.5, 41.0, 24.5, 29.0, 30.0, 27.5, 32.0, 33.0, 41.0, 45.5,
                       46.5, 22.0, 23.0, 27.5, 40.0, 41.0, 45.5, 53.5, 54.5, 59.0, 27.5, 32.0, 34.25, 45.5, 50.0, 50.0, 59.0,
                       63.5, 65.75]
    elseif pid == 2
        @test Array(yarr[:]) == [34.25, 36.5, 41.0, 50.0, 50.0, 54.5, 65.75, 68.0, 72.5, 41.0, 45.5, 46.5, 54.5, 59.0, 60.0, 72.5, 77.0,
                       78.0, 53.5, 54.5, 59.0, 67.0, 68.0, 72.5, 85.0, 86.0, 90.5, 59.0, 63.5, 65.75, 72.5, 77.0, 81.5, 90.5,
                       95.0, 99.5, 65.75, 68.0, 72.5, 81.5, 86.0, 90.5, 99.5, 104.0, 108.5]
    else
        @test Array(yarr[:]) == [72.5, 77.0, 78.0, 90.5, 95.0, 96.0, 108.5, 113.0, 114.0, 85.0, 86.0, 90.5, 103.0, 104.0, 108.5, 106.0,
                       107.0, 111.5, 90.5, 95.0, 99.5, 108.5, 113.0, 117.5, 111.5, 116.0, 120.5, 99.5, 104.0, 108.5, 117.5,
                       122.0, 126.5, 120.5, 125.0, 129.5, 108.5, 113.0, 114.0, 126.5, 131.0, 132.0, 129.5, 134.0, 135.0]
    end
#! format: on
    p = @allocated Spaces.weighted_dss!(y0, dss_buffer)
    iamroot && @test p ≤ 46200
end
