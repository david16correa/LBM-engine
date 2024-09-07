#= ==========================================================================================
=============================================================================================
misc functions
=============================================================================================
========================================================================================== =#

mean(v) = sum(v) / length(v)

#= ==========================================================================================
=============================================================================================
scalar and vector fild arithmetic auxilary functions -
=============================================================================================
========================================================================================== =#

function scalarFieldTimesVector(a::Array, V::Vector)
    return [a * V for a in a]
end

function vectorFieldDotVector(F::Array, v::Vector)
    return [dot(F, v) for F in F]
end

function vectorFieldDotVectorField(V::Array, W::Array)
    return [dot(V[id], W[id]) for id in eachindex(IndexCartesian(), V)]
end

function cross(v::Vector, w::Vector)
    dim = 0
    length(v) |> lenV -> (lenV == length(w)) ? (dim = lenV) : error("dimension mismatch!")
    dim == 2 && (return v[1]*w[2] - v[2]*w[1])
    dim == 3 && (return [v[2]*w[3] - v[3]*w[2], -v[1]*w[3] + v[3]*w[1], v[1]*w[2] - v[2]*w[1]])
end

#= I know this method is highly questionable, but it was born out of the need to compute the tangential
velocity using the position vector and the angular velocity in two dimensions. Ω happens to be a scalar
in two dimensions, but momentarily using three dimensions results in a simpler algorithm. =#
cross(omega::Real, V::Vector) = cross([0; 0; omega], [V; 0])[1:2]

function vectorCrossVectorField(V::Vector, W = Array)
    return [cross(V, W) for W in W]
end

function vectorFieldCrossVectorField(V::Array, W = Array)
    return [cross(V[id], W[id]) for id in eachindex(IndexCartesian(), V)]
end

vectorFieldCrossVector(V::Array, W::Vector) = - vectorCrossVectorField(W, V)

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

function pbcMatrixShift(M::Union{Array, SparseMatrixCSC, BitArray}, Δ::Vector{Int64})
    return size(M) |> sizeM -> [pbcIndexShift(1:sizeM[i], Δ[i]) for i in eachindex(sizeM)] |> shiftedIndices -> M[shiftedIndices...]
end

#= ==========================================================================================
=============================================================================================
wall and fluid nodes functions 
=============================================================================================
========================================================================================== =#

function wallNodes(massDensity::Array{Float64};
    walledDimensions = :default
)
    # the size, dimensions, and side length of the density field are saved
    sizeM = size(massDensity)
    dims, len = length(sizeM), sizeM[1];

    # the wallMap is initialized as an boolean array filled with zeroes,
    # and the indices of the density field are saved.
    wallMap = sizeM |> zeros .|> Bool
    indices = [1:i for i in sizeM];

    # by default, all dimensions are walled
    (walledDimensions == :default) ? (walledDimensions = eachindex(indices)) : nothing

    # for each dimension, a padding will be added. To do this, a set of auxilary indices will be needed.
    auxIndices = copy(indices);
    paddingRanges = (1:1, len:len);

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

function bounceBackPrep(wallRegion::Union{SparseMatrixCSC, BitArray}, velocities::Vector{LBMvelocity}; returnStreamingInvasionRegions = false)
    cs = [velocity.c for velocity in velocities];

    streamingInvasionRegions = [(pbcMatrixShift(wallRegion, -c) .|| wallRegion) .⊻ wallRegion for c in cs]

    returnStreamingInvasionRegions && return streamingInvasionRegions

    oppositeVectorId = [findfirst(x -> x == -c, cs) for c in cs]

    return streamingInvasionRegions, oppositeVectorId
end

#= ==========================================================================================
=============================================================================================
graphics stuff
=============================================================================================
========================================================================================== =#

function createFigDirs()
    !isdir("figs") && mkdir("figs")
    !isdir("figs/$(today())") && mkdir("figs/$(today())")
end

function createAnimDirs()
    !isdir("anims") && mkdir("anims")
    !isdir("anims/$(today())") && mkdir("anims/$(today())")
end

function save_jpg(name::String, fig::Figure)
    nameJPG = name*".jpg"
    save(".output.png", fig)
    if Sys.islinux()
        run(`convert .output.png $nameJPG`)
        run(`rm .output.png`);
    elseif Sys.isapple()
        run(`magick .output.png $nameJPG`)
        run(`rm .output.png`);
    elseif Sys.iswindows()
        namePNG = name*".png"
        run(`mv .output.png $nameJPG`)
        run(`rm .output.png $namePNG`);
    end
end

"the fluid velocity plot is generated and saved."
function plotFluidVelocity(model::LBMmodel;
    saveFig = true, 
    t = :default,
    fluidVelocity = :default, 
    maximumFluidSpeed = :default
)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    (t == :default) ? (t = model.time[end]) : nothing

    (fluidVelocity == :default) ? (fluidVelocity = model.fluidVelocity) : nothing

    if maximumFluidSpeed == :default
        maximumFluidSpeed = (model.fluidVelocity .|> norm) |> maximum
    end

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(fluidVelocity)/model.fluidParams.c_s, alpha = 0.7,
        colorrange = (0, maximumFluidSpeed/model.fluidParams.c_s), 
        highclip = :red, # truncate the colormap 
        axis=(
            title = "fluid velocity, t = $(t |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm, label = "Mach number (M = u/cₛ)"
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    #--------------------------------------vector field---------------------------------------
    indices = range(1, stop = length(model.spaceTime.x), length = 11) |> collect .|> round .|> Int64
    vectorFieldX = model.spaceTime.x[indices];
    pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
    vec = [fluidVelocity[i,j] for i ∈ eachindex(model.spaceTime.x)[indices] for j ∈ eachindex(model.spaceTime.x)[indices]];
    vec = 0.07 .* vec ./ maximumFluidSpeed;
    nonZeroVec = (vec .|> norm) .> 0.007
    arrows!(fig[1,1], pos[nonZeroVec], vec[nonZeroVec],
        arrowsize = 10,
        align = :center
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    if saveFig
        createFigDirs()
        save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
    else
        return fig, ax
    end
end

"the momentum density plot is generated and saved."
function plotMomentumDensity(model::LBMmodel;
    saveFig = true, 
    t = :default,
    momentumDensity = :default, 
    maximumMomentumDensity = :default
)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    (t == :default) ? (t = model.time[end]) : nothing

    (momentumDensity == :default) ? (momentumDensity = model.momentumDensity) : nothing

    if maximumMomentumDensity == :default
        maximumMomentumDensity = (model.momentumDensity .|> norm) |> maximum
    end

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, norm.(momentumDensity), alpha = 0.7,
        colorrange = (0, maximumMomentumDensity), 
        highclip = :red, # truncate the colormap 
        axis=(
            title = "momentum density, t = $(t |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm,
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    #--------------------------------------vector field---------------------------------------
    indices = range(1, stop = length(model.spaceTime.x), length = 11) |> collect .|> round .|> Int64
    vectorFieldX = model.spaceTime.x[indices];
    pos = [Point2(i,j) for i ∈ vectorFieldX for j ∈ vectorFieldX];
    vec = [momentumDensity[i,j] for i ∈ eachindex(model.spaceTime.x)[indices] for j ∈ eachindex(model.spaceTime.x)[indices]];
    vec = 0.07 .* vec ./ maximumMomentumDensity;
    nonZeroVec = (vec .|> norm) .> 0.007
    arrows!(fig[1,1], pos[nonZeroVec], vec[nonZeroVec],
        arrowsize = 10, 
        align = :center
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    if saveFig
        createFigDirs()
        save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
    else
        return fig, ax
    end
end


"the mass density plot is generated and saved."
function plotMassDensity(model::LBMmodel;
    saveFig = true,
    t = :default,
    massDensity = :default, 
    maximumMassDensity = :default,
    minimumMassDensity = :default
)
    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    (t == :default) ? (t = model.time[end]) : nothing

    (massDensity == :default) ? (massDensity = model.massDensity) : nothing

    if maximumMassDensity == :default
        maximumMassDensity = massDensity |> maximum
    end

    if minimumMassDensity == :default
        minimumMassDensity = massDensity[model.boundaryConditionsParams.wallRegion .|> b -> !b] |> minimum |> x -> maximum([0, x])
    end

    minimumMassDensity ≈ maximumMassDensity && (minimumMassDensity = 0);
    maximumMassDensity ≈ minimumMassDensity && (maximumMassDensity = 1);

    #----------------------------------heatmap and colorbar---------------------------------
    fig, ax, hm = heatmap(model.spaceTime.x, model.spaceTime.x, massDensity, 
        colorrange = (minimumMassDensity, maximumMassDensity), 
        lowclip = :black, # truncate the colormap 
        axis=(
            title = "mass density, t = $(t |> x -> round(x; digits = 2))",
            aspect = 1,
        ),
    );
    ax.xlabel = "x"; ax.ylabel = "y";
    Colorbar(fig[:, end+1], hm,
        #=ticks = (-1:0.5:1, ["$i" for i ∈ -1:0.5:1]),=#
    );
    xlims!(xlb, xub);
    ylims!(xlb, xub);

    if saveFig
        createFigDirs()
        save_jpg("figs/$(today())/LBM figure $(Time(now()))", fig)
    else
        return fig, ax
    end
end

"The animation of the fluid velocity evolution is created."
function anim8fluidVelocity(model::LBMmodel; verbose = false, framerate = 30)

    verbose && (outputTimes = range(1, stop = length(model.time), length = 50) |> collect .|> round)

    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumFluidSpeed = 1.;

    isdir(".tmp") && run(`rm -r .tmp`)
    mkdir(".tmp")

    fluidVelocities = [] |> Vector{Matrix{Vector{Float64}}};
    for t in eachindex(model.time)
        hydroVariablesUpdate!(model; time = t);
        append!(fluidVelocities, [model.fluidVelocity]);
    end

    maximumFluidSpeed = (fluidVelocities .|> M -> norm.(M)) .|> maximum |> maximum


    for t in eachindex(model.time)
        animationFig, animationAx = plotFluidVelocity(model; 
            saveFig = false, 
            t = model.time[t],
            fluidVelocity = fluidVelocities[t],
            maximumFluidSpeed = maximumFluidSpeed
        )
        save(".tmp/$(t).png", animationFig)

        verbose && t in outputTimes && print("\r t = $(model.time[t])")
    end
    print("\r");

    createAnimDirs()
    createVid = `ffmpeg -loglevel quiet -framerate $(framerate) -i .tmp/%d.png -c:v libx264 -pix_fmt yuv420p anims/.output.mp4`
    run(createVid)
    run(`rm -r .tmp`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/.output.mp4 $(name)`);
end

"The animation of the fluid velocity evolution is created."
function anim8momentumDensity(model::LBMmodel; verbose = false, framerate = 30)

    verbose && (outputTimes = range(1, stop = length(model.time), length = 50) |> collect .|> round)

    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    maximumMomentumDensity = 1.;

    isdir(".tmp") && run(`rm -r .tmp`)
    mkdir(".tmp")

    momentumDensities = [] |> Vector{Matrix{Vector{Float64}}};
    for t in eachindex(model.time)
        hydroVariablesUpdate!(model; time = t);
        append!(momentumDensities, [model.momentumDensity]);
    end

    maximumMomentumDensity = (momentumDensities .|> M -> norm.(M)) .|> maximum |> maximum

    for t in eachindex(model.time)
        animationFig, animationAx = plotMomentumDensity(model; 
            saveFig = false,
            t = model.time[t],
            momentumDensity = momentumDensities[t],
            maximumMomentumDensity = maximumMomentumDensity
        )
        save(".tmp/$(t).png", animationFig)

        verbose && t in outputTimes && print("\r t = $(model.time[t])")
    end
    print("\r");

    createAnimDirs()
    createVid = `ffmpeg -loglevel quiet -framerate $(framerate) -i .tmp/%d.png -c:v libx264 -pix_fmt yuv420p anims/.output.mp4`
    run(createVid)
    run(`rm -r .tmp`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/.output.mp4 $(name)`);
end

"The animation of the mass density evolution is created."
function anim8massDensity(model::LBMmodel; verbose = false, framerate = 30)

    verbose && (outputTimes = range(1, stop = length(model.time), length = 50) |> collect .|> round)

    xlb, xub = model.spaceTime.x |> V -> (minimum(V), maximum(V));

    massDensities = [massDensityGet(model; time = t) for t in eachindex(model.time)]

    maximumMassDensity = (massDensities .|> maximum) |> maximum
    minimumMassDensity = [massDensity[model.boundaryConditionsParams.wallRegion .|> b -> !b] |> minimum for massDensity in massDensities] |> minimum |> x -> maximum([0, x])

    isdir(".tmp") && run(`rm -r .tmp`)
    mkdir(".tmp")

    for t in eachindex(model.time)
        animationFig, animationAx = plotMassDensity(model; 
            saveFig = false,
            t = model.time[t],
            massDensity = massDensities[t],
            maximumMassDensity = maximumMassDensity,
            minimumMassDensity = minimumMassDensity
        )
        save(".tmp/$(t).png", animationFig)

        verbose && t in outputTimes && print("\r t = $(model.time[t])")
    end
    print("\r");

    createAnimDirs()
    createVid = `ffmpeg -loglevel quiet -framerate $(framerate) -i .tmp/%d.png -c:v libx264 -pix_fmt yuv420p anims/.output.mp4`
    run(createVid)
    run(`rm -r .tmp`)
    name = "anims/$(today())/LBM simulation $(Time(now())).mp4"
    run(`mv anims/.output.mp4 $(name)`);
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
