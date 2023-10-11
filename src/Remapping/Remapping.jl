module Remapping

using LinearAlgebra, StaticArrays

import ClimaComms
import ..DataLayouts,
    ..Geometry,
    ..Spaces,
    ..Topologies,
    ..Meshes,
    ..Operators,
    ..Fields,
    ..Hypsography

using ..RecursiveApply

include("interpolate_array.jl")
include("distributed_remapping.jl")

end
