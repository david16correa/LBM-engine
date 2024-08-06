#= ==========================================================================================
=============================================================================================
misc functions
=============================================================================================
========================================================================================== =#

function checkIdInModel(id::Int64, model::LBMmodel)
    (id in eachindex(model.distributions[end])) ? nothing : (error("No distribution with id $(id) was found!")) 
end

mean(v) = sum(v) / length(v)

#= ==========================================================================================
=============================================================================================
scalar and vector fild arithmetic auxilary functions -
=============================================================================================
========================================================================================== =#

dot(v::Vector, w::Vector) = v .* w |> sum

norm(T) = √(sum(el for el ∈ T.*T))

function scalarFieldTimesVector(a::Array, V::Vector)
    return [a * V for a in a]
end

function vectorFieldDotVector(F::Array, v::Vector)
    return [dot(F, v) for F in F]
end

function vectorFieldDotVectorField(V::Array, W::Array)
    return size(V) |> sizeV -> [dot(V[id], W[id]) for id in eachindex(IndexCartesian(), V)]
end

#= ==========================================================================================
=============================================================================================
shift auxilary functions 
=============================================================================================
========================================================================================== =#

function pbcIndexShift(indices::UnitRange{Int64}, Δ::Int64)
    if Δ > 0
        return [indices[end-Δ+1:end]; indices[1:end-Δ]]
    elseif Δ < 0
        # originalmente era [indices[(Δ+1):end]; indices[1:Δ]] con un shift positivo, pero Δ < 0
        return [indices[(-Δ+1):end]; indices[1:-Δ]]
    else
        return indices
    end
end

function pbcMatrixShift(M::Union{Array{Float64}, SparseMatrixCSC, BitArray}, Δ::Vector{Int64})
    return size(M) |> sizeM -> [pbcIndexShift(1:sizeM[i], Δ[i]) for i in eachindex(sizeM)] |> shiftedIndices -> M[shiftedIndices...]
end

#= ==========================================================================================
=============================================================================================
wall and fluid nodes functions 
=============================================================================================
========================================================================================== =#

function wallNodes(ρ::Array{Float64}, fluidSpeed::Int64; walledDimensions = [-1])
    # the size, dimensions, and side length of the density field are saved
    sizeM = size(ρ)
    dims, len = length(sizeM), sizeM[1];

    # the wallMap is initialized as an boolean array filled with zeroes,
    # and the indices of the density field are saved.
    wallMap = sizeM |> zeros .|> Bool
    indices = [1:i for i in sizeM];

    # by default, all dimensions are walled
    (walledDimensions == [-1]) ? (walledDimensions = eachindex(indices)) : nothing

    # for each dimension, a padding will be addd. To do this, a set of auxilary indices will be needed.
    auxIndices = copy(indices);
    paddingRanges = (1:fluidSpeed, len-fluidSpeed+1:len);

    # the padding is added in every dimension
    for id in walledDimensions, paddingRange in paddingRanges
        auxIndices[id] = paddingRange;
        wallMap[auxIndices...] .= 1;
        auxIndices = copy(indices)
    end

    #  the final wall map is returned as a sparse matrix
    (dims > 2) ? (return wallMap) : (return wallMap |> sparse)
    #  SparseArrays.jl only works for 1D and 2D. Look into SparseArrayKit.jl for higher dimensional compatibility!!
end

#= ==========================================================================================
=============================================================================================
bounce-back boundary conditions
=============================================================================================
========================================================================================== =#

function bounceBackPrep(wallRegion::Union{SparseMatrixCSC, BitArray}, velocities::Vector{LBMvelocity})
    cs = [velocity.c for velocity in velocities];

    streamingInvasionRegions = [(pbcMatrixShift(wallRegion, -c) .|| wallRegion) .⊻ wallRegion for c in cs]

    oppositeVectorId = [findfirst(x -> x == -c, cs) for c in cs]

    return streamingInvasionRegions, oppositeVectorId
end

#= ==========================================================================================
=============================================================================================
pressure difference boundary conditions
=============================================================================================
========================================================================================== =#

function auxNodesPrep(sizeM::Tuple, pressurizedDimensions::Vector{Int64}, N::Int64)
    auxSystemSize = [s for s in sizeM]; auxSystemSize[pressurizedDimensions] .+= 2;
    auxSystemMainRegion = [1:i for i in sizeM]; auxSystemMainRegion[pressurizedDimensions] .= [2:N+1];
    auxSystemIds = [1:i |> collect for i in auxSystemSize];
    return auxSystemSize, auxSystemMainRegion, auxSystemIds
end

function auxNodesId(id::Int64, model::LBMmodel)
    id += 1;
    outIds = copy(model.boundaryConditionsParams.auxSystemIds);
    outIds[model.boundaryConditionsParams.pressurizedDimensions] .= [[id]]
    return outIds
end

function auxNodesId(id::Vector{Int64}, model::LBMmodel)
    id .+= 1;
    outIds = copy(model.boundaryConditionsParams.auxSystemIds);
    outIds[model.boundaryConditionsParams.pressurizedDimensions] .= [id]
    return outIds
end

function auxNodesCreate(M::Array, model::LBMmodel)
    paddedM = [zero(M[1]) for _ in zeros(model.boundaryConditionsParams.auxSystemSize...)];
    paddedM[model.boundaryConditionsParams.auxSystemMainRegion...] = M
    return paddedM
end

function auxNodesMassDensityCreate(M::Array{Float64}, model::LBMmodel)
    N = model.boundaryConditionsParams.N

    M = auxNodesCreate(M, model)
    M[auxNodesId(0, model)...] = M[auxNodesId(N, model)...] |> ρN -> ρN + reshape(model.boundaryConditionsParams.ρH, size(ρN)) .- mean(ρN);
    M[auxNodesId(N+1, model)...] = M[auxNodesId(1, model)...] |> ρ1 -> ρ1 + reshape(model.boundaryConditionsParams.ρL, size(ρ1)) .- mean(ρ1);

    return M
end

function auxNodesCreate!(model::LBMmodel)
    N = model.boundaryConditionsParams.N

    model.ρ = auxNodesCreate(model.ρ, model)
    model.ρ[auxNodesId(0, model)...] = model.ρ[auxNodesId(N, model)...] |> ρN -> ρN + reshape(model.boundaryConditionsParams.ρH, size(ρN)) .- mean(ρN);
    model.ρ[auxNodesId(N+1, model)...] = model.ρ[auxNodesId(1, model)...] |> ρ1 -> ρ1 + reshape(model.boundaryConditionsParams.ρL, size(ρ1)) .- mean(ρ1);

    model.ρu = auxNodesCreate(model.ρu, model)
    model.ρu[auxNodesId(0, model)...] = model.ρu[auxNodesId(N, model)...];
    model.ρu[auxNodesId(N+1, model)...] = model.ρu[auxNodesId(1, model)...];

    model.u = [zero(model.ρu[1]) for _ in model.ρu];
    ((model.ρ .≈ 0) .|> b -> !b) |> ids -> (model.u[ids] = model.ρu[ids] ./ model.ρ[ids]);

    model.distributions[end] = [auxNodesCreate(distribution, model) for distribution in model.distributions[end]]
end

function auxNodesRemove(M::Array, model::LBMmodel)
    return M[auxNodesId(1:model.boundaryConditionsParams.N |> collect, model)...]
end

function auxNodesRemove!(model::LBMmodel)
    model.ρ = auxNodesRemove(model.ρ, model)
    model.ρu = auxNodesRemove(model.ρu, model)
    model.u = auxNodesRemove(model.u, model)
    model.distributions[end] = [auxNodesRemove(distribution, model) for distribution in model.distributions[end]]
end

#= ==========================================================================================
=============================================================================================
graphics stuff
=============================================================================================
========================================================================================== =#

function save_jpg(name::String, fig::Figure)
    namePNG = name*".png"
    nameJPG = name*".jpg"
    save(namePNG, fig) 
    run(`magick $namePNG $nameJPG`)
    run(`rm $namePNG`)
end

"The animation of the fluid velocity evolution is created."
function anim8fluidVelocity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumFluidSpeed = 1.;

    mkdir("tmp")

    us = [] |> Vector{Matrix{Vector{Float64}}};
    for t in eachindex(model.time)
        hydroVariablesUpdate!(model; time = t);
        append!(us, [model.u]);
    end

    maximumFluidSpeed = (us .|> M -> norm.(M)) .|> maximum |> maximum

    for t in eachindex(model.time)
        #----------------------------------heatmap and colorbar---------------------------------
        animationFig, animationAx, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(us[t]), alpha = 0.7,
            colorrange = (0, maximumFluidSpeed), 
            highclip = :red, # truncate the colormap 
            axis=(
                title = "fluid velocity, t = $(model.time[t] |> x -> round(x; digits = 2))",
                aspect = 1,
            ),
        );
        animationAx.xlabel = "x"; animationAx.ylabel = "y";
        Colorbar(animationFig[:, end+1], hm,
            #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
        );
        #--------------------------------------vector field---------------------------------------
        vectorFieldX = model.spaceTime.x[1:10:end];
        pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
        vec = [us[t][i,j] for i ∈ eachindex(model.spaceTime.x)[1:10:end] for j ∈ eachindex(model.spaceTime.x)[1:10:end]];
        vec = 0.07 .* vec ./ maximumFluidSpeed;
        arrows!(animationFig[1,1], pos, vec, 
            arrowsize = 10, 
            align = :center
        );
        xlims!(xlb, xub);
        ylims!(xlb, xub);
        save("tmp/$(t).png", animationFig)
    end

    run(`./createAnim.sh`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/output.mp4 $(name)`)
end

"The animation of the fluid velocity evolution is created."
function anim8momentumDensity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumFluidSpeed = 1.;

    mkdir("tmp")

    ρus = [] |> Vector{Matrix{Vector{Float64}}};
    for t in eachindex(model.time)
        hydroVariablesUpdate!(model; time = t);
        append!(ρus, [model.ρu]);
    end

    maximumFluidSpeed = (ρus .|> M -> norm.(M)) .|> maximum |> maximum

    for t in eachindex(model.time)
        #----------------------------------heatmap and colorbar---------------------------------
        animationFig, animationAx, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(ρus[t]), alpha = 0.7,
            colorrange = (0, maximumFluidSpeed), 
            highclip = :red, # truncate the colormap 
            axis=(
                title = "momentum density, t = $(model.time[t] |> x -> round(x; digits = 2))",
                aspect = 1,
            ),
        );
        animationAx.xlabel = "x"; animationAx.ylabel = "y";
        Colorbar(animationFig[:, end+1], hm,
            #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
        );
        #--------------------------------------vector field---------------------------------------
        vectorFieldX = model.spaceTime.x[1:10:end];
        pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
        vec = [ρus[t][i,j] for i ∈ eachindex(model.spaceTime.x)[1:10:end] for j ∈ eachindex(model.spaceTime.x)[1:10:end]];
        vec = 0.07 .* vec ./ maximumFluidSpeed;
        arrows!(animationFig[1,1], pos, vec, 
            arrowsize = 10, 
            align = :center
        );
        xlims!(xlb, xub);
        ylims!(xlb, xub);
        save("tmp/$(t).png", animationFig)
    end

    run(`./createAnim.sh`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/output.mp4 $(name)`)
end

"The animation of the mass density evolution is created."
function anim8massDensity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    ρs = [massDensity(model; time = t) for t in eachindex(model.time)]

    maximumMassDensity = (ρs .|> maximum) |> maximum
    minimumMassDensity = [ρ[model.boundaryConditionsParams.wallRegion .|> b -> !b] |> minimum for ρ in ρs] |> minimum |> x -> maximum([0, x])

    mkdir("tmp")

    for t in eachindex(model.time)
        #----------------------------------heatmap and colorbar---------------------------------
        animationFig, animationAx, hm = heatmap(model.spaceTime.x, model.spaceTime.x, ρs[t], 
            colorrange = (minimumMassDensity, maximumMassDensity), 
            lowclip = :black, # truncate the colormap 
            axis=(
                title = "mass density, t = $(model.time[t] |> x -> round(x; digits = 2))",
                aspect = 1,
            ),
        );
        animationAx.xlabel = "x"; animationAx.ylabel = "y";
        Colorbar(animationFig[:, end+1], hm,
            #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
        );
        xlims!(xlb, xub);
        ylims!(xlb, xub);
        save("tmp/$(t).png", animationFig)
    end

    run(`./createAnim.sh`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/output.mp4 $(name)`)
end

"the fluid velocity plot is generated and saved."
function plotFluidVelocity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumFluidSpeed = (model.u .|> norm) |> maximum

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(model.u), alpha = 0.7,
        colorrange = (0, maximumFluidSpeed), 
        highclip = :red, # truncate the colormap 
        axis=(
            title = "fluid velocity, t = $(model.time[end] |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm,
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    #--------------------------------------vector field---------------------------------------
    vectorFieldX = model.spaceTime.x[1:10:end];
    pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
    vec = [model.u[i,j] for i ∈ eachindex(model.spaceTime.x)[1:10:end] for j ∈ eachindex(model.spaceTime.x)[1:10:end]];
    vec = 0.07 .* vec ./ maximumFluidSpeed;
    arrows!(fig[1,1], pos, vec, 
        arrowsize = 10, 
        align = :center
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
end

"the momentum density plot is generated and saved."
function plotMomentumDensity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumMomentumDensity = (model.ρu .|> norm) |> maximum

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(model.ρu), alpha = 0.7,
        colorrange = (0, maximumMomentumDensity), 
        highclip = :red, # truncate the colormap 
        axis=(
            title = "momentum density, t = $(model.time[end] |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm,
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    #--------------------------------------vector field---------------------------------------
    vectorFieldX = model.spaceTime.x[1:10:end];
    pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
    vec = [model.ρu[i,j] for i ∈ eachindex(model.spaceTime.x)[1:10:end] for j ∈ eachindex(model.spaceTime.x)[1:10:end]];
    vec = 0.07 .* vec ./ maximumMomentumDensity;
    arrows!(fig[1,1], pos, vec, 
        arrowsize = 10, 
        align = :center
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
end


"the mass density plot is generated and saved."
function plotMassDensity(model::LBMmodel)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    ρs = [massDensity(model; time = t) for t in eachindex(model.time)]

    maximumMassDensity = (ρs .|> maximum) |> maximum
    minimumMassDensity = [ρ[model.boundaryConditionsParams.wallRegion .|> b -> !b] |> minimum for ρ in ρs] |> minimum |> x -> maximum([0, x])

    t = length(model.time)

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, ρs[t], 
        colorrange = (minimumMassDensity, maximumMassDensity), 
        lowclip = :black, # truncate the colormap 
        axis=(
            title = "mass density, t = $(model.time[t] |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm,
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
end

#= ==========================================================================================
=============================================================================================
some velocity sets 
=============================================================================================
========================================================================================== =#

cs = [
      [0],
      #======#
      [1],
      [-1]
];
ws = [
      2/3,
      #======#
      1/6,
      1/6
];
D1Q3 = [LBMvelocity(cs[i], ws[i]) for i in eachindex(cs)];

cs = [
      [0,0],
      #======#
      [1,0],
      [-1,0],
      [0,1],
      [0,-1],
      #======#
      [1,1],
      [-1,1],
      [1,-1],
      [-1,-1]
];
ws = [
      4/9,
      #======#
      1/9,
      1/9,
      1/9,
      1/9,
      #======#
      1/36,
      1/36,
      1/36,
      1/36
];
D2Q9 = [LBMvelocity(cs[i], ws[i]) for i in eachindex(cs)];

cs = [
      [0,0,0], 
      #======#
      [1,0,0],
      [0,1,0],
      [0,0,1],
      [-1,0,0],
      [0,-1,0],
      [0,0,-1],
      #======#
      [1,1,0],
      [1,-1,0],
      [-1,1,0],
      [-1,-1,0],
      [0,1,1],
      [0,1,-1],
      [0,-1,1],
      [0,-1,-1],
      [1,0,1],
      [1,0,-1],
      [-1,0,1],
      [-1,0,-1],
      #======#
      [1,1,1],
      [1,1,-1],
      [1,-1,1],
      [1,-1,-1],
      [-1,1,1],
      [-1,1,-1],
      [-1,-1,1],
      [-1,-1,-1]
];
ws = [
      8/27,
      #======#
      2/27,
      2/27,
      2/27,
      2/27,
      2/27,
      2/27,
      #======#
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      1/54,
      #======#
      1/216,
      1/216,
      1/216,
      1/216,
      1/216,
      1/216,
      1/216,
      1/216
];
D3Q27 = [LBMvelocity(cs[i], ws[i]) for i in eachindex(cs)];
