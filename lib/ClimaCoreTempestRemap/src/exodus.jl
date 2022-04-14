"""
    write_exodus(filename, topology::Topology2D; normalize_coordinates=true)

Write the topology to an Exodus-formatted NetCDF file.

It tries to adhere to the Exodus II specification, but it is primarily intended
for use with TempestRemap.

Note: the generated meshes will use a different ordering of nodes and elements
than those generated by TempestRemap itself.

Options:
- `normalize_coordinates`: if true, the coordinates are normalized to be on the
  unit sphere (this is required for use with TempestRemap)

# References
- EXODUS II: A finite element data model:
  https://www.osti.gov/biblio/10102115-exodus-ii-finite-element-data-model
"""
function write_exodus(
    filename,
    topology::Topologies.Topology2D;
    normalize_coordinates = true,
)

    len_string = 33
    len_line = 81
    four = 4
    time_step = 0

    num_elem = Topologies.nlocalelems(topology)
    num_nodes = length(Topologies.vertices(topology))
    num_dim = Geometry.ncomponents(Meshes.coordinate_type(topology))
    num_qa_rec = 1
    num_el_blk = 1
    num_el_in_blk1 = num_elem
    num_nod_per_el1 = 4
    num_att_in_blk1 = 1

    connect1 = Array{Int32}(undef, (num_nod_per_el1, num_elem)) # array of unique vertex indices for each element
    coord = Array{Float64}(undef, (num_nodes, num_dim))  # array of coordinates for each unique vertex

    for (uv, vertex) in enumerate(Topologies.vertices(topology))
        for (e, v) in vertex
            connect1[v, e] = uv
        end
        (e, v) = first(vertex)
        c = Float64.(Geometry.components(Meshes.coordinates(topology, e, v)))
        if normalize_coordinates
            c = c ./ norm(c)
        end
        coord[uv, :] .= c
    end

    # init_data
    NCDataset(filename, "c") do dts

        # dimensions
        defDim(dts, "len_string", len_string)
        defDim(dts, "len_line", len_line)
        defDim(dts, "four", four)
        defDim(dts, "time_step", time_step)
        defDim(dts, "num_dim", num_dim)
        defDim(dts, "num_nodes", num_nodes)
        defDim(dts, "num_elem", num_elem)
        defDim(dts, "num_qa_rec", num_qa_rec)
        defDim(dts, "num_el_blk", num_el_blk)
        defDim(dts, "num_el_in_blk1", num_el_in_blk1)
        defDim(dts, "num_nod_per_el1", num_nod_per_el1)
        defDim(dts, "num_att_in_blk1", num_att_in_blk1)

        # global attibutes
        dts.attrib["title"] = "ClimaCore.jl mesh from $(topology)"
        dts.attrib["api_version"] = Float32(5.0)
        dts.attrib["version"] = Float32(5.0)
        dts.attrib["floating_point_word_size"] = sizeof(Float64)
        dts.attrib["file_size"] = 0

        # variables
        var_time_whole = defVar(dts, "time_whole", Float64, ("time_step",))
        var_qa_records = defVar(
            dts,
            "qa_records",
            Char,
            ("len_string", "four", "num_qa_rec"),
        ) # quality assurance record (code name, QA descriptor, date, time) - here '\0's
        var_coor_names =
            defVar(dts, "coor_names", Char, ("len_string", "num_dim"))
        var_eb_names =
            defVar(dts, "eb_names", Char, ("len_string", "num_el_blk"))
        var_eb_status = defVar(dts, "eb_status", Int32, ("num_el_blk",))
        var_eb_prop1 = defVar(dts, "eb_prop1", Int32, ("num_el_blk",))
        var_attrib1 = defVar(
            dts,
            "attrib1",
            Float64,
            ("num_att_in_blk1", "num_el_in_blk1"),
        )
        var_connect1 = defVar(
            dts,
            "connect1",
            Int32,
            ("num_nod_per_el1", "num_el_in_blk1"),
        )
        var_global_id1 = defVar(dts, "global_id1", Int32, ("num_el_in_blk1",))
        var_edge_type1 = defVar(
            dts,
            "edge_type1",
            Int32,
            ("num_nod_per_el1", "num_el_in_blk1"),
        ) # tempest specific
        var_coord = defVar(dts, "coord", Float64, ("num_nodes", "num_dim"))

        # variable attributes
        var_connect1.attrib["elem_type"] = "SHELL4"
        var_eb_prop1.attrib["name"] = "ID"

        # variable values
        dt = now()
        qa_records = (
            "ClimaCoreTempestRemap.jl",
            string(PkgVersion.@Version),
            Dates.format(dt, dateformat"mm/dd/yyyy"), # mm/dd/yy is in the spec
            Dates.format(dt, dateformat"HH:MM:SS"),
        )
        for (i, rec) in enumerate(qa_records)
            vrec = collect(rec)
            var_qa_records[axes(vrec, 1), i] = vrec
        end
        var_coord[:, :] = coord
        var_connect1[:, :] = connect1
        var_coor_names[1, :] = ['x', 'y', 'z']
        var_eb_prop1[:] = Int32(1)
        var_eb_status[:] = Int32(1)
        var_global_id1[:] = Int32.(1:num_el_in_blk1)
        var_attrib1[:, :] .= 1.0
        var_edge_type1[:, :] .= 0
        nothing
    end
end
