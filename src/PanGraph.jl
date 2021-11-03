module PanGraph

using GZip
using Rematch
using Random: seed!

include("graph.jl")

# ------------------------------------------------------------------------
# errors

struct Error <: Exception
    msg::AbstractString
end
Base.showerror(io::IO, e::Error) = print(io, "PanGraph Error: ", e.msg)

function panic(msg...) 
    print(stderr, string(msg...))
    exit(2)
end

function open(func, path)
    endswith(path, ".gz") && return GZip.open(func, path)
    return Base.open(func, path)
end

# ------------------------------------------------------------------------
# subcommands and arguments

include("args.jl")
using .Commands

# ---------------------------
# All subcommands go here

include("build.jl")
include("generate.jl")
include("polish.jl")

pangraph = Command(
    "pangraph",
    "pangraph <command> [arguments]",
    "pangraph is a tool for aligning large sets of genomes in the presence of horizontal gene transfer",
    "passed directly to the chosen command",
    [
     Build,
     Generate,
     Polish,
    ],
)

function main(args)
    if length(args) == 0
        usage(pangraph)
        return 2
    end

    return run(pangraph, parse(pangraph, args))
end

function julia_main()::Cint
    try
        return main(ARGS)
    catch
        # TODO: more sophisticated error handling
        return 1
    end
end

if !isdefined(Base, :active_repl)
    main(ARGS)
end

end

