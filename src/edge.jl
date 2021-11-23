module Edges

using ..Paths
using ..Nodes
using ..Blocks
using ..Graphs

export edges, deparalog!

struct Position
    path  :: Path
    node  :: Tuple{Node{Block},Node{Block}}
    index :: Tuple{Int,Int} # positions on path
    locus :: Int # breakpoint on sequence
end

function isolates(positions::Array{Position,1})
    isolate = Dict{String,Array{Position,1}}()
    for pos in positions
        if pos.path.name ∈ keys(isolate)
            push!(isolate[pos.path.name],pos)
        else
            isolate[pos.path.name] = [ pos ]
        end
    end

    return isolate
end

function next(x::Position, blk::Block)
    function index(i::Int)
        i ≤ 0 && return length(x.path)+i
        i > length(x.path) && return i - length(x.path)
        return i
    end

    function isright(num, of)
        if num == 1 && of == length(x.path)
            return true
        end
        if of == 1 && num == length(x.path)
            return false
        end

        return num > of
    end

    i, j = (blk == x.node[1].block) ? (x.index[1], x.index[2]) : (x.index[2], x.index[1])
    n, m, k, l, pos = if isright(j, i) #j > i
        ι = index(i-1)
        x.path.node[i], x.path.node[ι], i, ι, x.path.position[j]
    else
        ι = index(i+1)
        x.path.node[i], x.path.node[ι], i, ι, x.path.position[i]
    end

    if (n.block.uuid > m.block.uuid) || (n.block.uuid == m.block.uuid && pointer_from_objref(n) > pointer_from_objref(m))
        n, m = m, n
        k, l = l, k
    end

    function imax(a,b)
        L = length(x.path.node)
        if (a == L && b == 1) || (b == L && a == 1)
            return 1
        end
        return max(a,b)
    end

    pos = x.path.position[imax(k,l)]

    return Position(x.path, (n, m), (k, l), pos)
    #=
    i,s,d = if blk == x.node[1].block
        x.index[2],
        x.node[1].strand ? +1 : -1,
        index(minimum(x.index)+1)
    else
        x.index[1],
        x.node[2].strand ? +1 : -1,
        index(minimum(x.index)+1)
    end
    p = index(i + s)

    if x.locus != x.path.position[d]
        @infiltrate
    end

    n₁  = x.path.node[i]
    n₂  = x.path.node[p]
    pos = x.path.position[index(i+s+d)]

    if n₁.block.uuid > n₂.block.uuid
        i, p = p, i
        n₁, n₂ = n₂, n₁
    end

    return Position(
        x.path,
        (n₁, n₂),
        (i, p),
        pos
    )
    =#
end

Base.show(io::IO, x::Position) = Base.show(io,
    (
        path=x.path.name,
        blocks=(x.node[1].block, x.node[2].block),
        strand=(x.node[1].strand, x.node[2].strand),
        index=(x.index[1], x.index[2]),
        locus=x.locus
    )
)

mutable struct Edge
    block  :: Tuple{Block, Block}
    invert :: Bool # changes strand
    nodes  :: Array{Position}
end

Breakpoints = Tuple{Array{Tuple{Int,Int},1},Array{Tuple{Int,Int},1}}

function equals(e::Edge, block1::Block, block2::Block, invert::Bool)
    return e.block[1] == block1 && e.block[2] == block2 && invert == e.invert
end

Edge(block₁::Block, block₂::Block, invert::Bool, pos::Position) = Edge((block₁, block₂), invert, Position[pos])

function edges(G)
    edgeset = Edge[]

    function addedge!(side₁, side₂, path, locus)
        if (side₁.node.block.uuid > side₂.node.block.uuid) || (side₁.node.block.uuid == side₂.node.block.uuid && pointer_from_objref(side₁.node) > pointer_from_objref(side₂.node))
            side₁, side₂ = side₂, side₁
        end

        invert   = side₁.node.strand ⊻ side₂.node.strand
        position = Position(
            path,
            (side₁.node, side₂.node),
            (side₁.index,side₂.index),
            locus
        )
        for edge in edgeset
            if equals(edge, side₁.node.block, side₂.node.block, invert)
                push!(edge.nodes, position)
                return
            end
        end
        # if we are here, then this is a new edge
        push!(edgeset, Edge(side₁.node.block, side₂.node.block, invert, position))
    end

    for path in values(G.sequence)
        for (i,link) in enumerate(path.node[2:end])
            node = path.node[i]
            addedge!(
                (node=node,index=i),
                (node=link,index=i+1),
                path, path.position[i+1]
            )
        end

        if path.circular
            addedge!(
                (node=path.node[end],index=length(path.node)),
                (node=path.node[1],index=1),
                path, path.position[1]
            )
        end
    end

    return edgeset
end

function deparalog!(G)
    edgeset = edges(G)

    # collect all edges for each block, segregated by position
    vertex = Dict(
        block => (
            edge = Set{Edge}(),
            link = Dict{Position,Edge}(),
        ) for block in values(G.block)
    )

    function duplicates(vertex, block)
        loci = [
            let
                if k.node[1].block == block
                    (k.path.name,k.index[1])
                elseif k.node[2].block == block
                    (k.path.name,k.index[2])
                else
                    error("bad indexing")
                end
            end for k in keys(vertex)
        ] |> unique
        names = unique(map(first, loci))
        return length(loci) > length(names)
    end

    function connect(edge, block)
        for locus in edge.nodes
            push!(vertex[block].edge, edge)
            vertex[block].link[locus] = edge
        end
    end

    for edge in edgeset
        block = edge.block
        connect(edge, block[1])
        connect(edge, block[2])
    end

    touched = Set{Block}()
    blocks  = collect(values(G.block))

    for block ∈ blocks
        block ∉ touched || continue
        vert = vertex[block]

        duplicates(vert.link,block) || continue

        split = true
        links = Dict{Tuple{Edge,Edge}, Set{Position}}()
        for edge in vert.edge
            dest = Dict{Edge,Array{Position,1}}()
            for pos in edge.nodes
                x = next(pos,block)
                x ∈ keys(vert.link) || @goto nosplit

                e = vert.link[x]
                if e ∈ keys(dest)
                    push!(dest[e], x)
                else
                    dest[e] = [x]
                end
            end

            if length(dest) > 1
                # XXX: last effort to split paralogs:
                # if the set positions contained by dest edges
                # is equal to the the set positions we flow to,
                # then we are still transitive
                linkpos = reduce(union, map((link)->Set(link.nodes), collect(keys(dest))))
                edgepos = reduce(union, map((v)->Set(v), collect(values(dest))))
                if linkpos == edgepos
                    for link in keys(dest)
                        if (link,edge) ∉ keys(links)
                            linkpos = Set(link.nodes)
                            links[edge,link] = Set(
                                pos for pos in edge.nodes if next(pos, block) ∈ linkpos
                            )
                        end
                    end
                else @label nosplit
                    split = false
                    break
                end
            else
                link = collect(keys(dest))[1]
                if (link,edge) ∉ keys(links)
                    links[(edge,link)] = Set(edge.nodes)
                end
            end
        end

        (split && length(links) > 1) || continue

        seennodes = Set{Node}()
        for positions in collect(values(links))[2:end]
            new = Block(block.sequence, block.gaps)
            for pos in positions
                i,j = if pos.node[1].block == block
                    (1,2)
                elseif pos.node[2].block == block
                    (2,1)
                else
                    error("bad edge")
                end
                push!(touched, pos.node[j].block)

                # rewire node to new block
                n = pos.node[i]
                push!(seennodes,n)
                new.mutate[n] = pop!(block.mutate, n)
                new.insert[n] = pop!(block.insert, n)
                new.delete[n] = pop!(block.delete, n)
                n.block = new
            end

            G.block[new.uuid] = new
        end
    end
end

#=
function breakpoints(G)
    edgeset = edges(G)

    # collect all edges for each block, segregated by position
    vertex = Dict(
        block => (
            edge = Set{Edge}(),
            link = Dict{Position,Edge}(),
        ) for block in values(G.block)
    )

    function connect(edge, block)
        for locus in edge.nodes
            push!(vertex[block].edge, edge)
            vertex[block].link[locus] = edge
        end
    end

    for edge in edgeset
        block = edge.block
        connect(edge, block[1])
        connect(edge, block[2])
    end

    breakpoints = Dict{Tuple{String,String}, Breakpoints}()
    for block ∈ values(G.block)
        vert = vertex[block]
        for edge in vert.edge
            dest = Dict{Edge,Array{Position,1}}()
            for pos in edge.nodes
                #next(pos,block) ∉ keys(vert.link) && @infiltrate # XXX: for debugging

                x = next(pos, block)
                e = vert.link[x]
                if e ∈ keys(dest)
                    push!(dest[e], x)
                else
                    dest[e] = [x]
                end
            end

            length(dest) > 1 || continue # if all edges flow to same spot

            # iterate over all partitions
            groups = collect(keys(dest))
            for (i,g1) in enumerate(groups)
                ig1 = isolates(dest[g1])
                for g2 in groups[i+1:end]
                    ig2 = isolates(dest[g2])
                    for (name1, positions1) in ig1
                        for (name2, positions2) in ig2
                            name1 != name2 || continue # don't look for breaks within the same genome

                            #=
                            if (((name1 ==  "NZ_CP007727" && name2 == "NZ_CP008827")
                             ||  (name2 ==  "NZ_CP007727" && name1 == "NZ_CP008827"))
                             &&  block.uuid == "USBZGBXYEO")
                                @infiltrate
                            end
                            =#

                            index1 = map((p)->p.index, positions1)
                            index2 = map((p)->p.index, positions2)

                            key, val1, val2 = if name1 > name2
                                (name2, name1),
                                index2, index1
                            else
                                (name1, name2),
                                index1, index2
                            end

                            if key ∈ keys(breakpoints)
                                append!(breakpoints[key][1],val1)
                                append!(breakpoints[key][2],val2)
                            else
                                breakpoints[key] = (val1,val2)
                            end
                        end
                    end
                end
            end
        end
    end

    return breakpoints
end
=#

#=
function breakpoints(G)
    edgeset = edges(G)

    # collect all edges for each block, segregated by position
    vertex = Dict(
        block => (
            left  = Dict{Position,Edge}(),
            right = Dict{Position,Edge}()
        ) for block in values(G.block)
    )

    function connect(edge, block)
        for locus in edge.nodes
            i, j = if locus.node[1].block == block
                1, 2
            elseif locus.node[2].block == block
                2, 1
            else
                error("bad edge")
            end
            N = length(locus.path.node)

            strand  = locus.node[i].strand
            toright = if ((locus.index[i] % N) + 1) == locus.index[j]
                true
            elseif ((locus.index[j] % N) + 1) == locus.index[i]
                false
            else
                # XXX: debugging assumptions
                # remove when confident
                error("bad index arithmetic")
            end

            if toright ⊻ strand
                vertex[block].right[locus] = edge
            else
                vertex[block].left[locus] = edge
            end
        end
    end

    for edge in edgeset
        block = edge.block
        connect(edge, block[1])
        connect(edge, block[2])
    end

    breakpoints = Dict{Tuple{String,String}, Breakpoints}()

    for block ∈ values(G.block) # iterate over all blocks
        for edge in vertex[block] # iterate over left & right breaks
            loci = collect(keys(edge))
            for (i,pos₁) in enumerate(loci) # all breakpoints on left/right edge
                e₁ = edge[pos₁]
                for pos₂ in loci[i+1:end]
                    pos₁.path.name != pos₂.path.name || continue

                    e₂ = edge[pos₂]
                    if e₁ != e₂
                        if (((pos₁.path.name == "NZ_CP011980" &&  pos₂.path.name == "NZ_CP011989")
                        ||   (pos₂.path.name == "NZ_CP011980" &&  pos₁.path.name == "NZ_CP011989"))
                        && block.uuid == "CNEPHYFJAA")
                            pos1 = pos₁
                            pos2 = pos₂
                            @infiltrate
                        end

                        key, val = if pos₁.path.name > pos₂.path.name
                            (pos₂.path.name, pos₁.path.name),
                            (pos₂.index, pos₁.index)
                        else
                            (pos₁.path.name, pos₂.path.name),
                            (pos₁.index, pos₂.index)
                        end
                        if key ∈ keys(breakpoints)
                            push!(breakpoints[key][1],val[1])
                            push!(breakpoints[key][2],val[2])
                        else
                            breakpoints[key] = ([val[1]], [val[2]])
                        end
                    end
                end
            end
        end
    end

    return breakpoints, function(name₁::AbstractString, name₂::AbstractString)
        name₁ == name₂ && return Breakpoints([])
        name₁ > name₂  && return breakpoints[(name₂,name₁)]
        return breakpoints[(name₁,name₂)]
    end
end
=#



end
